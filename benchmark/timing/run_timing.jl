#!/usr/bin/env julia
#
# Timing benchmark of the original R/Fortran code and the Julia port
# (TIMING_BENCHMARK_PLAN.md; usage in benchmark/timing/README.md).
#
#   julia --project=benchmark/timing benchmark/timing/run_timing.jl [options]
#
# Options:
#   --suite quick|standard|full   which suite of config.toml (default quick)
#   --reps N                      override the suite's repetitions
#   --only FAMILY,...             run only these families (startup, model, sampling,
#                                 constraints, engine, io, analysis, endtoend)
#   --out DIR                     results root (default: %LOCALAPPDATA%\GeocarbTiming)
#   --rscript PATH                Rscript executable (default: RSCRIPT, PATH, C:\Program Files\R)
#   --skip-r / --skip-julia       run one implementation only
#   --allow-synced                allow a results folder inside a cloud-synced folder
#   --keep-work                   keep the large temporary files (results\...\work\tmp)
#   --install-r-packages          install the R packages bench and ps into your user library
#                                 if missing (only used by the benchmark; decision T2)
#   --dry-run                     print the plan of processes and exit
#
# Every measurement runs in a fresh process; R and Julia processes alternate in a random
# order within each repetition (plan §6.4). Results: <out>/<host>_<stamp>/report.md.

include(joinpath(@__DIR__, "lib", "common.jl"))
using TOML: TOML
using Random: Random, shuffle
include(joinpath(@__DIR__, "env", "capture_env.jl"))

# ------------------------------------------------------------------------------------
# options and configuration
# ------------------------------------------------------------------------------------

function parse_options(args)
    o = Dict{String,Any}(
        "suite" => "quick",
        "reps" => nothing,
        "only" => nothing,
        "out" => nothing,
        "rscript" => nothing,
        "skip-r" => false,
        "skip-julia" => false,
        "allow-synced" => false,
        "keep-work" => false,
        "dry-run" => false,
        "install-r-packages" => false,
    )
    flags = ("skip-r", "skip-julia", "allow-synced", "keep-work", "dry-run", "install-r-packages")
    i = 1
    while i <= length(args)
        a = args[i]
        startswith(a, "--") || error("unexpected argument $a")
        k = a[3:end]
        haskey(o, k) || error("unknown option $a (see the header of run_timing.jl)")
        if k in flags
            o[k] = true
        else
            i += 1
            i <= length(args) || error("$a needs a value")
            o[k] = args[i]
        end
        i += 1
    end
    return o
end

# Same search as test/legacy_comparison/run_comparison.jl.
function find_rscript(explicit)
    explicit !== nothing && return explicit
    haskey(ENV, "RSCRIPT") && return ENV["RSCRIPT"]
    r = Sys.which("Rscript")
    r !== nothing && return r
    if Sys.iswindows()
        for base in (raw"C:\Program Files\R", joinpath(homedir(), "AppData", "Local", "Programs", "R"))
            isdir(base) || continue
            versions = sort(
                filter(d -> startswith(d, "R-"), readdir(base));
                by=d -> something(tryparse(VersionNumber, replace(d, "R-" => "")), v"0"),
            )
            for v in reverse(versions)
                f = joinpath(base, v, "bin", "Rscript.exe")
                isfile(f) && return f
            end
        end
    end
    return error("Rscript not found. Install R, put Rscript on the PATH, or pass --rscript / set RSCRIPT.")
end

mutable struct Session
    o::Dict{String,Any}
    general::Dict{String,Any}
    suite::Dict{String,Any}
    suite_name::String
    reps::Int
    dir::String
    work::String
    session::String
    rscript::Union{Nothing,String}
    legacy::String
    exports::String
    instr::String
    r_trees::Dict{String,String}          # R variant => legacy tree (R/, input_data/, fortran/)
    ffi_libs::Vector{String}              # "name|main|supp" for ccall
    exact_variant::String
    mem_limit::Float64
    rng::Random.Xoshiro
    raw::RawWriter                        # rows written by the orchestrator itself (cold runs)
    planned::Vector{String}
    failures::Vector{String}
end

sget(s::Session, k, default) = get(s.suite, k, default)
libext() =
    if Sys.iswindows()
        ".dll"
    elseif Sys.isapple()
        ".dylib"
    else
        ".so"
    end

# ------------------------------------------------------------------------------------
# running processes
# ------------------------------------------------------------------------------------

const JULIA = Base.julia_cmd()

function job_file(s::Session, name::AbstractString, d::AbstractDict)
    base = Dict{String,Any}(
        "session_id" => s.session,
        "repo" => REPO_DIR,
        "exports_dir" => s.exports,
        "instrumented_dir" => s.instr,
        "memory_limit_bytes" => string(round(Int, s.mem_limit)),
        "seed" => string(get(s.general, "seed", 2026)),
    )
    merge!(base, d)
    haskey(base, "tmp_dir") || (base["tmp_dir"] = joinpath(s.work, "tmp", name))
    return write_job(joinpath(s.dir, "jobs", name * ".txt"), base)
end

function raw_paths(s, impl, family)
    return Dict(
        "raw_file" => joinpath(s.dir, "raw", "$(impl)_$(family).csv"),
        "per_sample_file" => joinpath(s.dir, "raw", "$(impl)_$(family)_per_sample.csv"),
    )
end

function run_logged(s::Session, name::AbstractString, cmd::Cmd)
    push!(s.planned, "$name: $(join(cmd.exec, ' '))")
    s.o["dry-run"] && return (true, 0.0)
    log = joinpath(s.dir, "logs", name * ".log")
    print(rpad(name, 46), " ")
    t0 = time()
    ok = try
        run(pipeline(ignorestatus(cmd); stdout=log, stderr=log)).exitcode == 0
    catch err
        open(io -> println(io, "could not start: ", err), log, "a")
        false
    end
    t = time() - t0
    println(ok ? "" : "FAILED  ", round(t; digits=1), " s")
    ok || push!(s.failures, "$name (see logs/$name.log)")
    return (ok, t)
end

function julia_cmd(s::Session, script::AbstractString, job::AbstractString; threads=1)
    c = `$JULIA --project=$(HARNESS_DIR) --startup-file=no -t $threads $(joinpath(HARNESS_DIR, script)) $job`
    return addenv(c, "OPENBLAS_NUM_THREADS" => "1", "JULIA_NUM_THREADS" => string(threads))
end
function r_cmd(s::Session, script::AbstractString, job::AbstractString)
    return addenv(`$(s.rscript) $(joinpath(HARNESS_DIR, script)) $job`, "OPENBLAS_NUM_THREADS" => "1")
end

function julia_job(s, family, rep, script; name_suffix="", threads=1, extra...)
    name = "julia_$(family)$(name_suffix)_rep$(rep)"
    d = merge(
        raw_paths(s, "julia", family),
        Dict{String,Any}("rep" => string(rep)),
        Dict{String,Any}(string(k) => v for (k, v) in extra),
    )
    return () -> run_logged(s, name, julia_cmd(s, script, job_file(s, name, d); threads=threads))
end

function r_job(s, family, rep, script; variant="R0", name_suffix="", extra...)
    name = "R_$(family)$(name_suffix)_$(variant)_rep$(rep)"
    d = merge(
        raw_paths(s, "R", family),
        Dict{String,Any}("rep" => string(rep), "variant" => variant, "legacy_dir" => s.r_trees[variant]),
        Dict{String,Any}(string(k) => v for (k, v) in extra),
    )
    return () -> run_logged(s, name, r_cmd(s, script, job_file(s, name, d)))
end

"Run the jobs of one repetition in a random order (plan §6.4: R and Julia interleaved)."
function run_interleaved(s::Session, jobs)
    for f in shuffle(s.rng, collect(jobs))
        f()
    end
end

# ------------------------------------------------------------------------------------
# preparation: instrumented copies, Fortran variants, shared ensemble
# ------------------------------------------------------------------------------------

function prepare_instrumented!(s::Session)
    s.rscript === nothing && return nothing
    ok, _ = run_logged(
        s,
        "prepare_instrumented_copies",
        `$(s.rscript) $(joinpath(HARNESS_DIR, "r", "instrumented", "make_instrumented.R")) $(joinpath(s.legacy, "R")) $(s.instr)`,
    )
    return ok || error("could not generate the instrumented R copies (logs/prepare_instrumented_copies.log)")
end

"Copy R/ and input_data/ of the legacy tree, and put a Fortran build into its fortran/."
function make_tree(s::Session, name::AbstractString)
    t = mkpath(joinpath(s.work, "legacy_$name"))
    for sub in ("R", "input_data")
        isdir(joinpath(t, sub)) || cp(joinpath(s.legacy, sub), joinpath(t, sub))
    end
    mkpath(joinpath(t, "fortran"))
    return t
end

const VARIANT_FLAGS = Dict("r_default" => "", "O0" => "-O0", "O3" => "-O3", "O3_native" => "-O3 -march=native")

function build_fortran!(s::Session, name::AbstractString)
    tree = make_tree(s, name)
    rbin = joinpath(dirname(s.rscript), Sys.iswindows() ? "R.exe" : "R")
    src = mkpath(joinpath(s.work, "build_$name"))
    # R CMD SHLIB puts PKG_FCFLAGS *before* R's own FCFLAGS, whose -O2 would then win. So the
    # variant's flags replace the optimisation flags of R's FCFLAGS/FFLAGS in a Makevars file
    # (R_MAKEVARS_USER); r_default keeps R's flags unchanged.
    makevars = joinpath(src, "Makevars")
    open(makevars, "w") do io
        if name != "r_default"
            for var in ("FCFLAGS", "FFLAGS")
                base = s.o["dry-run"] ? "" : strip(read(`$rbin CMD config $var`, String))
                base = replace(base, r"(^|\s)-O\S*" => " ", r"(^|\s)-march=\S*" => " ", r"(^|\s)-mtune=\S*" => " ")
                println(io, var, " = ", strip(base * " " * VARIANT_FLAGS[name]))
            end
        end
    end
    flags = "-fno-range-check"
    for lib in ("run_geocarb", "run_geocarb_supp")
        cp(joinpath(s.legacy, "fortran", "src", lib * ".f90"), joinpath(src, lib * ".f90"); force=true)
        out = joinpath(tree, "fortran", lib * libext())
        # make (used by R CMD SHLIB) treats backslashes as escapes: pass the path with "/"
        cmd = setenv(
            `$rbin CMD SHLIB -o $(replace(out, '\\' => '/')) $(lib * ".f90")`,
            merge(copy(ENV), Dict("PKG_FFLAGS" => flags, "PKG_FCFLAGS" => flags, "R_MAKEVARS_USER" => makevars));
            dir=src,
        )
        ok, t = run_logged(s, "build_fortran_$(name)_$lib", cmd)
        if ok && !s.o["dry-run"] && !isfile(out)
            ok = false
            msg = "build_fortran_$(name)_$lib: R CMD SHLIB reported success but $out was not created"
            @warn msg
            push!(s.failures, msg)
        end
        if ok && !s.o["dry-run"]
            record!(
                s.raw;
                impl="fortran",
                variant=name,
                component="M6",
                subcomponent="build $lib (R CMD SHLIB)",
                wall_s=t,
                mode="cold",
                notes="variant flags: $(VARIANT_FLAGS[name]) (replacing R's -O/-march); informational",
            )
        end
        if !ok
            record!(
                s.raw;
                impl="fortran",
                variant=name,
                component="M6",
                subcomponent="build $lib (R CMD SHLIB)",
                wall_s=NaN,
                mode="cold",
                checksum_ok=false,
                notes="build failed; variant skipped (see logs)",
            )
            return nothing
        end
    end
    return tree
end

function prepare_fortran!(s::Session)
    s.rscript === nothing && return nothing
    shipped = joinpath(s.legacy, "fortran")
    has_shipped = isfile(joinpath(shipped, "run_geocarb" * libext()))
    ffi = mkpath(joinpath(s.work, "ffi"))
    function add_ffi(name, dir)
        main = joinpath(ffi, "run_geocarb__$(name)" * libext())
        supp = joinpath(ffi, "run_geocarb_supp__$(name)" * libext())
        s.o["dry-run"] || cp(joinpath(dir, "run_geocarb" * libext()), main; force=true)
        s.o["dry-run"] ||
            !isfile(joinpath(dir, "run_geocarb_supp" * libext())) ||
            cp(joinpath(dir, "run_geocarb_supp" * libext()), supp; force=true)
        return push!(s.ffi_libs, "$name|$main|$supp")
    end
    if has_shipped
        s.r_trees["R0"] = s.legacy
        add_ffi("shipped", shipped)
        s.exact_variant = "shipped"
    else
        @warn "no compiled library in legacy/fortran: R0 and H0 use an r_default build (exact checks become tolerance checks)"
        tree = build_fortran!(s, "r_default")
        tree === nothing && error("could not build the Fortran library")
        s.r_trees["R0"] = tree
        add_ffi("r_default", joinpath(tree, "fortran"))
    end
    if sget(s, "fortran_variants", false)
        for v in get(s.general, "fortran_variants", String[])
            (v == "r_default" && !has_shipped) && continue
            tree = build_fortran!(s, v)
            tree === nothing && continue
            add_ffi(v, joinpath(tree, "fortran"))
            v == get(s.general, "r1_variant", "O3") && (s.r_trees["R1"] = tree)
        end
    end
end

"Shared ensemble for A/G (plan §5.3), cached under the results root."
function prepare_ensemble!(s::Session)
    n = sget(s, "analysis_n", 0)
    n > 0 || return nothing
    n >= 3334 || error(
        "analysis_n = $n: analysis_and_plots.R needs at least 3334 accepted samples " *
        "(10 000 rows in the merged 30 % experiment, for deltaT2X_samplesize)",
    )
    thr = get(s.suite, "analysis_threshold", 0.5)
    seed = get(s.general, "seed", 2026)
    dir = joinpath(dirname(s.dir), "cache", "ensemble_n$(n)_t$(thr)_s$(seed)")
    if !isfile(joinpath(dir, "lhs_param_ensemble.RData"))
        ok, _ = run_logged(
            s,
            "prepare_ensemble_julia",
            addenv(
                `$JULIA --project=$(HARNESS_DIR) --startup-file=no -t auto $(joinpath(HARNESS_DIR, "julia", "prepare_ensemble.jl")) $dir $n $thr $seed`,
            ),
        )
        ok || error("could not build the shared ensemble (logs/prepare_ensemble_julia.log)")
        if s.rscript !== nothing
            ok, _ = run_logged(
                s,
                "prepare_ensemble_R",
                `$(s.rscript) $(joinpath(HARNESS_DIR, "r", "prepare_ensemble.R")) $dir $(s.r_trees["R0"])`,
            )
            ok || error("could not convert the shared ensemble to .RData (logs/prepare_ensemble_R.log)")
        end
    end
    return dir
end

# ------------------------------------------------------------------------------------
# families
# ------------------------------------------------------------------------------------

function cold!(s::Session, impl, component, sub, cmd; notes="")
    ok, t = run_logged(
        s, "cold_$(impl)_$(component)_$(replace(sub, r"[^A-Za-z0-9]+" => "_"))_$(length(s.planned))", cmd
    )
    s.o["dry-run"] && return nothing
    return record!(
        s.raw;
        impl=impl,
        variant=impl == "R" ? "R0" : "J",
        component=component,
        subcomponent=sub,
        mode="cold",
        wall_s=ok ? t : NaN,
        checksum_ok=ok,
        threads=1,
        notes="whole process, timed from outside" * (isempty(notes) ? "" : "; " * notes),
    )
end

function family_startup!(s::Session)
    figdir = mkpath(joinpath(s.work, "tmp", "g1"))
    rlib = joinpath(s.r_trees["R0"], "fortran", "run_geocarb" * libext())
    rlib_r = replace(rlib, "\\" => "/")
    for i in 1:sget(s, "cold_reps", 5)
        tasks = Function[]
        if !s.o["skip-r"]
            push!(tasks, () -> cold!(s, "R", "S1", "empty process (Rscript -e 0)", `$(s.rscript) -e 0`))
            push!(
                tasks,
                () -> cold!(
                    s,
                    "R",
                    "S1",
                    "process + packages + dyn.load",
                    `$(s.rscript) -e "suppressPackageStartupMessages({library(lhs);library(CholWishart);library(MASS);library(abind);library(Hmisc)}); invisible(dyn.load('$rlib_r'))"`,
                ),
            )
            push!(
                tasks,
                () -> cold!(
                    s,
                    "R",
                    "S0",
                    "probe process (S1+S2+S3)",
                    r_cmd(
                        s,
                        "r/startup_probe.R",
                        job_file(
                            s,
                            "R_startup_probe_$i",
                            merge(
                                raw_paths(s, "R", "startup"),
                                Dict{String,Any}("rep" => string(i), "legacy_dir" => s.r_trees["R0"]),
                            ),
                        ),
                    ),
                ),
            )
            g1r = replace(joinpath(figdir, "r_$i.pdf"), "\\" => "/")
            push!(
                tasks,
                () -> cold!(
                    s,
                    "R",
                    "G1",
                    "first figure (fresh process)",
                    `$(s.rscript) -e "pdf('$g1r'); plot(1:10); invisible(dev.off())"`,
                ),
            )
        end
        if !s.o["skip-julia"]
            push!(tasks, () -> cold!(s, "julia", "S1", "empty process (julia -e 0)", `$JULIA --startup-file=no -e 0`))
            push!(
                tasks,
                () -> cold!(
                    s,
                    "julia",
                    "S1",
                    "process + using GeocarbPrecalibration",
                    `$JULIA --project=$(HARNESS_DIR) --startup-file=no -e "using GeocarbPrecalibration"`,
                ),
            )
            push!(
                tasks,
                () -> cold!(
                    s,
                    "julia",
                    "S0",
                    "probe process (S1+S2+S3)",
                    julia_cmd(
                        s,
                        "julia/startup_probe.jl",
                        job_file(
                            s,
                            "julia_startup_probe_$i",
                            merge(raw_paths(s, "julia", "startup"), Dict{String,Any}("rep" => string(i))),
                        ),
                    ),
                ),
            )
            g1j = joinpath(figdir, "julia_$i.pdf")
            push!(
                tasks,
                () -> cold!(
                    s,
                    "julia",
                    "G1",
                    "first figure (fresh process)",
                    `$JULIA --project=$(HARNESS_DIR) --startup-file=no -e "using CairoMakie; f = Figure(); lines!(Axis(f[1, 1]), 1:10); save(raw\"$g1j\", f)"`;
                    notes="plain; no PrecompileTools workload, no sysimage",
                ),
            )
        end
        run_interleaved(s, tasks)
    end
    if sget(s, "precompile", false) && !s.o["skip-julia"]
        cold!(
            s,
            "julia",
            "S1b",
            "precompile GeocarbPrecalibration (compilecache)",
            `$JULIA --project=$(HARNESS_DIR) --startup-file=no -e "Base.compilecache(Base.identify_package(\"GeocarbPrecalibration\"))"`;
            notes="package only; dependencies are cached once per depot",
        )
    end
end

function family_simple!(s::Session, family, rscript, jscript; rextra=Dict(), jextra=Dict(), r_variants=["R0"])
    for rep in 1:(s.reps)
        jobs = Function[]
        if !s.o["skip-r"] && rscript !== nothing
            for v in r_variants
                haskey(s.r_trees, v) && push!(jobs, r_job(s, family, rep, rscript; variant=v, rextra...))
            end
        end
        s.o["skip-julia"] || jscript === nothing || push!(jobs, julia_job(s, family, rep, jscript; jextra...))
        run_interleaved(s, jobs)
    end
end

csv(v) = join(string.(v), ",")

function family_model!(s::Session)
    exact = Dict("R0" => string(s.exact_variant == "shipped"), "R1" => "false")
    for rep in 1:(s.reps)
        jobs = Function[]
        if !s.o["skip-r"]
            for v in ("R0", "R1")
                haskey(s.r_trees, v) || continue
                push!(
                    jobs,
                    r_job(
                        s,
                        "model",
                        rep,
                        "r/bench_model.R";
                        variant=v,
                        exact=exact[v],
                        model_inputs=sget(s, "model_inputs", 1001),
                        supp_inputs=sget(s, "supp_inputs", 200),
                    ),
                )
            end
        end
        s.o["skip-julia"] || push!(
            jobs,
            julia_job(
                s,
                "model",
                rep,
                "julia/bench_model.jl";
                fortran_libs=join(s.ffi_libs, ","),
                exact_variant=s.exact_variant,
                model_inputs=sget(s, "model_inputs", 1001),
                supp_inputs=sget(s, "supp_inputs", 200),
            ),
        )
        run_interleaved(s, jobs)
    end
end

function family_engine!(s::Session)
    sizes = sget(s, "engine_sizes", Int[])
    chunk = sget(s, "engine_chunk", 1000)
    thr = sget(s, "engine_threshold", 0.3)
    common = (sizes=csv(sizes), chunk=chunk, threshold=thr)
    for rep in 1:(s.reps)
        jobs = Function[]
        if !s.o["skip-r"]
            for v in ("R0", "R1")
                haskey(s.r_trees, v) || continue
                push!(
                    jobs,
                    r_job(
                        s,
                        "engine",
                        rep,
                        "r/bench_engine.R";
                        variant=v,
                        mode="fixed",
                        common...,
                        verify_n=sget(s, "engine_verify_n", 2000),
                    ),
                )
            end
        end
        if !s.o["skip-julia"]
            push!(
                jobs,
                julia_job(
                    s,
                    "engine",
                    rep,
                    "julia/bench_engine.jl";
                    name_suffix="_1thread",
                    mode="fixed",
                    variants="J0,J1",
                    common...,
                ),
            )
            push!(
                jobs,
                julia_job(
                    s,
                    "engine",
                    rep,
                    "julia/bench_engine.jl";
                    name_suffix="_threads",
                    threads=Sys.CPU_THREADS,
                    mode="fixed",
                    variants="J2,J3",
                    common...,
                ),
            )
        end
        run_interleaved(s, jobs)
    end
    # once per session: E3, E4, E5, E6
    real = sget(s, "realistic", Any[])
    if !isempty(real)
        rchunk = min(chunk, 2_000)
        rate = get(s.general, "realistic_min_rate", 0.002)
        pairs = csv(["$(p[1]):$(p[2]):$(max(ceil(Int, p[2] / rate), 2rchunk))" for p in real])
        jobs = Function[]
        s.o["skip-r"] || push!(
            jobs,
            r_job(
                s,
                "engine",
                1,
                "r/bench_engine.R";
                name_suffix="_realistic",
                mode="realistic",
                realistic=pairs,
                chunk=rchunk,
            ),
        )
        if !s.o["skip-julia"]
            push!(
                jobs,
                julia_job(
                    s,
                    "engine",
                    1,
                    "julia/bench_engine.jl";
                    name_suffix="_realistic_1thread",
                    mode="realistic",
                    realistic=pairs,
                    chunk=rchunk,
                    variants="J1",
                ),
            )
            push!(
                jobs,
                julia_job(
                    s,
                    "engine",
                    1,
                    "julia/bench_engine.jl";
                    name_suffix="_realistic_threads",
                    mode="realistic",
                    threads=Sys.CPU_THREADS,
                    realistic=pairs,
                    chunk=rchunk,
                    variants="J2,J3",
                ),
            )
        end
        run_interleaved(s, jobs)
    end
    if !s.o["skip-julia"]
        tn = maximum(sizes; init=10_000)
        for t in sget(s, "thread_counts", Int[])
            k = t == 0 ? Sys.CPU_THREADS : t
            julia_job(
                s,
                "engine",
                1,
                "julia/bench_engine.jl";
                name_suffix="_E4_t$k",
                threads=k,
                mode="threads",
                n=tn,
                chunk=min(chunk, 1000),
                threshold=0.5,
            )()
        end
        julia_job(
            s,
            "engine",
            1,
            "julia/bench_engine.jl";
            name_suffix="_E6",
            mode="checkpoint",
            n=minimum(sizes; init=2000),
            chunk=min(chunk, 1000),
            threshold=thr,
        )()
    end
    for n in sget(s, "memory_sizes", Int[])
        mchunk = min(chunk, 10_000)
        if !s.o["skip-julia"]
            for design in ("global_lhs", "chunked_lhs"), cov in (false, true)
                need = julia_engine_bytes(n, mchunk; global_lhs=design == "global_lhs", covariances=cov)
                if need > s.mem_limit
                    record!(
                        s.raw;
                        variant="J",
                        component="E5",
                        workload="$design n=$n covariances=$cov",
                        n=n,
                        wall_s=NaN,
                        notes="skipped by the memory guard (about $(round(need / 1e9; digits = 1)) GB)",
                    )
                    continue
                end
                julia_job(
                    s,
                    "engine",
                    1,
                    "julia/bench_engine.jl";
                    name_suffix="_E5_$(design)_n$(n)_cov$(cov)",
                    mode="memory",
                    n=n,
                    chunk=mchunk,
                    design=design,
                    covariances=cov,
                )()
            end
        end
        if !s.o["skip-r"]
            need = r_engine_bytes(n, mchunk)
            if need > s.mem_limit
                record!(
                    s.raw;
                    impl="R",
                    variant="R0",
                    component="E5",
                    workload="GlobalLHS n=$n",
                    n=n,
                    wall_s=NaN,
                    notes="skipped by the memory guard (about $(round(need / 1e9; digits = 1)) GB)",
                )
            else
                r_job(s, "engine", 1, "r/bench_engine.R"; name_suffix="_E5_n$n", mode="memory", n=n, chunk=mchunk)()
            end
        end
    end
end

function family_io!(s::Session, ens)
    synced = get(s.general, "synced_dir", "")
    rdata = if ens === nothing
        ""
    else
        csv(filter(isfile, [joinpath(ens, "lhs_param_ensemble.RData"), joinpath(ens, "lhs_model_ensemble.RData")]))
    end
    return family_simple!(
        s,
        "io",
        "r/bench_io.R",
        "julia/bench_io.jl";
        rextra=Dict(:io_n => sget(s, "io_n", 2000), :synced_dir => synced),
        jextra=Dict(:io_n => sget(s, "io_n", 2000), :synced_dir => synced, :rdata_files => rdata),
    )
end

function family_analysis!(s::Session, ens)
    ens === nothing && return nothing
    # analysis_and_plots.R needs num_samples == ensemble size (its time-series correlations
    # pair vectors of both lengths) and >= 10 000 rows in the merged 30 % experiment.
    n = sget(s, "analysis_n", 0)
    figs = mkpath(joinpath(s.dir, "figures"))
    out = mkpath(joinpath(s.dir, "numbers"))
    for rep in 1:(s.reps)
        jobs = Function[]
        s.o["skip-r"] || push!(
            jobs,
            r_job(
                s,
                "analysis",
                rep,
                "r/bench_analysis.R";
                num_samples=n,
                verify_n=rep == 1 ? 1 : 0,
                ensemble_rdata=joinpath(ens, "lhs_param_ensemble.RData"),
                fig_dir=figs,
                out_dir=out,
            ),
        )
        s.o["skip-julia"] || push!(
            jobs,
            julia_job(
                s,
                "analysis",
                rep,
                "julia/bench_analysis.jl";
                num_samples=n,
                ensemble_jld2=joinpath(ens, "result.jld2"),
                fig_dir=figs,
                out_dir=out,
            ),
        )
        run_interleaved(s, jobs)
    end
end

function family_endtoend!(s::Session, ens)
    sget(s, "endtoend", false) || return nothing
    ens === nothing && error("endtoend needs the shared ensemble: set analysis_n in the suite")
    k = sget(s, "endtoend_accept", 100)
    ch = sget(s, "endtoend_chunk", 2000)
    common = Dict{String,Any}(
        "threshold" => string(sget(s, "endtoend_threshold", 0.5)),
        "n_accept" => string(k),
        "chunk" => string(ch),
        "n_cap" => string(max(ceil(Int, k / get(s.general, "realistic_min_rate", 0.002)), 2ch)),
        "num_samples" => string(sget(s, "analysis_n", 0)),
        "ensemble_rdata" => joinpath(ens, "lhs_param_ensemble.RData"),
        "ensemble_jld2" => joinpath(ens, "result.jld2"),
    )
    for rep in 1:(s.reps)
        tasks = Function[]
        if !s.o["skip-r"]
            push!(
                tasks,
                () -> begin
                    name = "R_endtoend_R0_rep$rep"
                    d = merge(
                        raw_paths(s, "R", "endtoend"),
                        common,
                        Dict{String,Any}("rep" => string(rep), "variant" => "R0", "legacy_dir" => s.r_trees["R0"]),
                    )
                    ok, t = run_logged(s, name, r_cmd(s, "r/pipeline_x1.R", job_file(s, name, d)))
                    record!(
                        s.raw;
                        impl="R",
                        variant="R0",
                        component="X1",
                        subcomponent="whole process",
                        rep=rep,
                        mode="cold",
                        wall_s=ok ? t : NaN,
                        checksum_ok=ok,
                        workload="threshold=$(common["threshold"]) accept=$(common["n_accept"])",
                    )
                end,
            )
        end
        if !s.o["skip-julia"]
            for v in ("J1", "J2", "J3")
                push!(
                    tasks,
                    () -> begin
                        name = "julia_endtoend_$(v)_rep$rep"
                        th = v == "J1" ? 1 : Sys.CPU_THREADS
                        d = merge(
                            raw_paths(s, "julia", "endtoend"),
                            common,
                            Dict{String,Any}("rep" => string(rep), "variant" => v),
                        )
                        ok, t = run_logged(
                            s, name, julia_cmd(s, "julia/pipeline_x1.jl", job_file(s, name, d); threads=th)
                        )
                        record!(
                            s.raw;
                            variant=v,
                            component="X1",
                            subcomponent="whole process",
                            rep=rep,
                            mode="cold",
                            threads=th,
                            wall_s=ok ? t : NaN,
                            checksum_ok=ok,
                            workload="threshold=$(common["threshold"]) accept=$(common["n_accept"])",
                        )
                    end,
                )
            end
        end
        run_interleaved(s, tasks)
    end
end

function sentinels!(s::Session, position)
    jobs = Function[]
    s.o["skip-julia"] ||
        push!(jobs, julia_job(s, "sentinel", 1, "calibration/sentinel.jl"; name_suffix="_$position", position=position))
    if !s.o["skip-r"]
        name = "R_sentinel_$position"
        push!(
            jobs,
            () -> run_logged(
                s,
                name,
                r_cmd(
                    s,
                    "calibration/sentinel.R",
                    job_file(
                        s,
                        name,
                        merge(raw_paths(s, "R", "sentinel"), Dict{String,Any}("rep" => "1", "position" => position)),
                    ),
                ),
            ),
        )
    end
    return run_interleaved(s, jobs)
end

# ------------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------------

function main(args)
    o = parse_options(args)
    cfg = TOML.parsefile(joinpath(HARNESS_DIR, "config.toml"))
    general = cfg["general"]
    haskey(cfg["suite"], o["suite"]) ||
        error("unknown suite $(o["suite"]); config.toml has $(join(keys(cfg["suite"]), ", "))")
    suite = cfg["suite"][o["suite"]]
    root = something(o["out"], isempty(general["results_root"]) ? default_results_root() : general["results_root"])
    if is_synced_path(root) && !o["allow-synced"]
        error(
            "results folder $root looks like a cloud-synced folder; the sync client distorts the timings and locks files " *
            "while they are written (plan §6.1). Use --out with a local folder, or --allow-synced to override.",
        )
    end
    exports = joinpath(REPO_DIR, "test", "legacy_comparison", "output")
    meta = joinpath(exports, "legacy_meta.txt")
    if !isfile(meta) || !occursin("n_sample: 1000", read(meta, String)) || !occursin("seed: 2026", read(meta, String))
        error(
            "the legacy-comparison exports (seed 2026, n = 1000) are missing in $exports. Run run_tests.bat " *
            "(or test/legacy_comparison/run_comparison.jl) first: speed is only measured on a version that passes parity.",
        )
    end
    stamp = Dates.format(Dates.now(), "yyyymmdd-HHMMSS")
    host = replace(gethostname(), r"[^A-Za-z0-9_-]" => "_")
    dir = joinpath(root, "$(host)_$(stamp)")
    for sub in ("raw", "jobs", "logs", "work")
        mkpath(joinpath(dir, sub))
    end
    reps = o["reps"] === nothing ? suite["reps"] : parse(Int, o["reps"])
    families = something(o["only"] === nothing ? nothing : split(o["only"], ","), suite["families"])
    rscript = o["skip-r"] ? nothing : find_rscript(o["rscript"])
    session = "$(host)_$(stamp)"
    s = Session(
        o,
        general,
        suite,
        o["suite"],
        reps,
        dir,
        joinpath(dir, "work"),
        session,
        rscript,
        joinpath(REPO_DIR, "legacy"),
        exports,
        joinpath(dir, "work", "instrumented"),
        Dict{String,String}(),
        String[],
        "",
        get(general, "memory_guard", 0.7) * total_memory(),
        Random.Xoshiro(get(general, "seed", 2026)),
        RawWriter(
            Dict(
                "raw_file" => joinpath(dir, "raw", "orchestrator.csv"),
                "per_sample_file" => joinpath(dir, "raw", "orchestrator_per_sample.csv"),
                "session_id" => session,
                "rep" => "1",
            ),
        ),
        String[],
        String[],
    )
    open(joinpath(dir, "session.toml"), "w") do io
        TOML.print(
            io,
            Dict(
                "suite" => o["suite"],
                "reps" => reps,
                "families" => String.(families),
                "options" => Dict(k => string(v) for (k, v) in o),
                "config" => cfg,
            );
            sorted=true,
        )
    end
    println("Timing benchmark, suite '$(o["suite"])', $(reps) repetition(s), families: $(join(families, ", "))")
    println("Results: $dir")

    t0 = time()
    if o["install-r-packages"] && rscript !== nothing && !o["dry-run"]
        run_logged(
            s,
            "install_r_packages",
            `$rscript -e "lib <- Sys.getenv('R_LIBS_USER'); dir.create(lib, recursive = TRUE, showWarnings = FALSE); .libPaths(c(lib, .libPaths())); for (p in c('bench', 'ps')) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, lib = lib, repos = 'https://cloud.r-project.org')"`,
        )
    end
    s.o["skip-r"] || prepare_instrumented!(s)
    if s.o["skip-r"]
        s.r_trees["R0"] = s.legacy
    else
        prepare_fortran!(s)
    end
    o["dry-run"] || capture_env(
        joinpath(dir, "env.toml");
        rscript=rscript,
        results_root=dir,
        legacy_libs=[
            joinpath(s.legacy, "fortran", "run_geocarb" * libext()),
            joinpath(s.legacy, "fortran", "run_geocarb_supp" * libext()),
        ],
    )
    ens = any(in(families), ("analysis", "io", "endtoend")) ? prepare_ensemble!(s) : nothing

    sentinels!(s, "start")
    for (k, fam) in enumerate(families)
        println("\n== $fam")
        if fam == "startup"
            family_startup!(s)
        elseif fam == "model"
            family_model!(s)
        elseif fam == "sampling"
            family_simple!(
                s,
                "sampling",
                "r/bench_sampling.R",
                "julia/bench_sampling.jl";
                rextra=Dict(
                    :lhs_sizes => csv(sget(s, "lhs_sizes", Int[])),
                    :sampler_n => sget(s, "sampler_n", 500),
                    :covariance_n => csv(sget(s, "covariance_n", Int[])),
                    :rng_draws => sget(s, "rng_draws", 10^7),
                ),
                jextra=Dict(
                    :lhs_sizes => csv(sget(s, "lhs_sizes", Int[])),
                    :sampler_n => sget(s, "sampler_n", 500),
                    :covariance_n => csv(sget(s, "covariance_n", Int[])),
                    :rng_draws => sget(s, "rng_draws", 10^7),
                ),
            )
        elseif fam == "constraints"
            family_simple!(s, "constraints", "r/bench_constraints.R", "julia/bench_constraints.jl")
        elseif fam == "engine"
            family_engine!(s)
        elseif fam == "io"
            family_io!(s, ens)
        elseif fam == "analysis"
            family_analysis!(s, ens)
        elseif fam == "endtoend"
            family_endtoend!(s, ens)
        else
            error("unknown family $fam")
        end
        k == cld(length(families), 2) && k < length(families) && sentinels!(s, "middle")
    end
    sentinels!(s, "end")

    if o["dry-run"]
        println("\nDry run: $(length(s.planned)) processes would be started:")
        foreach(p -> println("  ", p), s.planned)
        return nothing
    end
    o["keep-work"] || rm(joinpath(dir, "work", "tmp"); recursive=true, force=true)
    println("\nAll measurements done in $(round((time() - t0) / 60; digits = 1)) min. Writing the report ...")
    ok, _ = run_logged(
        s, "collect", `$JULIA --project=$(HARNESS_DIR) --startup-file=no $(joinpath(HARNESS_DIR, "collect.jl")) $dir`
    )
    isempty(s.failures) || println(
        "\nFailed processes (their rows are missing or marked checksum_ok = false):\n  ", join(s.failures, "\n  ")
    )
    return println("\nReport: ", joinpath(dir, ok ? "report.md" : "logs/collect.log"))
end

main(ARGS)
