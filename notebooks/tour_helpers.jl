# Helpers for the notebook tour (notebooks/tour.jl).
#
# Nothing in this file re-implements the model or the checks. The functions below call
# the package, run the repository's own test suite in subprocesses, and load the
# repository's own comparison code (test/legacy_comparison/compare.jl and
# plot_comparison.jl), so that the notebook shows exactly what CI checks. Keeping them
# here keeps the notebook readable; every function is short and documented.

using GeocarbPrecalibration
using CairoMakie
using InteractiveUtils  # versioninfo(); loaded by the REPL and IJulia, but not by Literate or scripts
using Markdown
using Printf
using Statistics
using Test
using TOML

const GP = GeocarbPrecalibration
const MK = CairoMakie.Makie

const ROOT = let d = pkgdir(GeocarbPrecalibration)
    d === nothing && error("GeocarbPrecalibration is not loaded from a checkout; run `julia notebooks/setup.jl`")
    d
end
const LEGACY_DIR = joinpath(ROOT, "legacy")
const COMPARISON_DIR = joinpath(ROOT, "test", "legacy_comparison")
const STORED_EXPORTS = joinpath(COMPARISON_DIR, "output")
const FIXTURE_DIR = joinpath(ROOT, "test", "fixtures", "fortran")

"""
Result of `notebooks/test_notebook.jl` on Julia 1.10: `:untested`, `:supported` or
`:unsupported`. Set it from the result of that test (the "Notebook" CI workflow runs it
on Julia 1.10 and on the newest release).
"""
const JULIA_110_STATUS = :supported

# ---------------------------------------------------------------------------------------
# look and feel

"Colours shared by every figure (the palette of test/legacy_comparison/plot_comparison.jl)."
const PALETTE = (
    legacy=MK.RGBf(0x52 / 255, 0x51 / 255, 0x4e / 255),
    julia=MK.RGBf(0x2a / 255, 0x78 / 255, 0xd6 / 255),
    post=MK.RGBf(0xeb / 255, 0x68 / 255, 0x34 / 255),
    fail=MK.RGBf(0xe3 / 255, 0x49 / 255, 0x48 / 255),
    f64=MK.RGBf(0x62 / 255, 0x50 / 255, 0xd6 / 255),
    ok=MK.RGBf(0x1a / 255, 0x7f / 255, 0x37 / 255),
    gold=MK.RGBf(0xd4 / 255, 0xa0 / 255, 0x17 / 255),
    grid=MK.RGBf(0.88, 0.88, 0.87),
)

"Makie theme of the notebook: light grid, no top/right spines, left-aligned titles."
function set_tour_theme!()
    return set_theme!(
        Theme(;
            fontsize=14,
            Axis=(;
                xgridcolor=PALETTE.grid,
                ygridcolor=PALETTE.grid,
                topspinevisible=false,
                rightspinevisible=false,
                titlealign=:left,
            ),
            Legend=(; framevisible=false),
        ),
    )
end

const _CALLOUT = Dict(:note => "ℹ️ **Note.**", :warn => "⚠️ **Warning.**", :ok => "✅", :danger => "⛔ **Stop.**")

"A highlighted paragraph (a Markdown block quote), e.g. `callout(:warn, \"text\")`."
callout(kind::Symbol, text::AbstractString) = Markdown.parse("> " * _CALLOUT[kind] * " " * text)

_esc(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
fmt(x::Real) = x == 0 ? "0" : (isnan(x) ? "–" : @sprintf("%.2e", x))
fmt(x) = string(x)

const BADGE = Dict(
    :pass => "<span class=\"gc-pass\">✔ pass</span>",
    :fail => "<span class=\"gc-fail\">✘ FAIL</span>",
    :skip => "<span class=\"gc-skip\">– skipped</span>",
    :error => "<span class=\"gc-fail\">✘ error</span>",
)
badge(ok::Bool) = BADGE[ok ? :pass : :fail]

# Styles of `html_table` and the badges. They were inline `style` attributes on every
# cell, which made the documentation page exceed Documenter's 200 KiB HTML limit (61% of
# the page was repeated styles). One copy now goes out with each table, so every table
# is styled on its own in Documenter and in Jupyter. `!important` reproduces the old
# inline precedence over the Documenter themes' `.content table td/th` rules (the dark
# theme's selectors are more specific than a class), so the tables look the same.
const TABLE_STYLE =
    "<style>" *
    "table.gc-tour{border-collapse:collapse!important;font-size:92%!important;margin:4px 0!important}" *
    "table.gc-tour caption{text-align:left;font-weight:600}" *
    "table.gc-tour th{text-align:left!important;padding:3px 10px!important;border-bottom:2px solid #d0d7de!important}" *
    "table.gc-tour td{padding:3px 10px!important;border-bottom:1px solid #eaeef2!important}" *
    ".gc-pass{color:#1a7f37;font-weight:600}.gc-fail{color:#cf222e;font-weight:600}.gc-skip{color:#6e7781}" *
    "</style>"

"""
    html_table(header, rows; caption = "", collapsed = nothing) -> HTML

A small styled table. `rows` holds already formatted cells (HTML allowed). With
`collapsed = "summary text"` the table is folded into a `<details>` block.
"""
function html_table(header, rows; caption::AbstractString="", collapsed=nothing)
    io = IOBuffer()
    print(io, TABLE_STYLE)
    collapsed === nothing || print(io, "<details><summary>", collapsed, "</summary>")
    print(io, "<table class=\"gc-tour\">")
    isempty(caption) || print(io, "<caption>", caption, "</caption>")
    print(io, "<thead><tr>")
    for h in header
        print(io, "<th>", h, "</th>")
    end
    print(io, "</tr></thead><tbody>")
    for r in rows
        print(io, "<tr>")
        for c in r
            print(io, "<td>", c, "</td>")
        end
        print(io, "</tr>")
    end
    print(io, "</tbody></table>")
    collapsed === nothing || print(io, "</details>")
    return HTML(String(take!(io)))
end

finite_or_nan(v) = [isfinite(x) ? Float64(x) : NaN for x in v]

# ---------------------------------------------------------------------------------------
# Julia version and environment

"""
    julia_version_check() -> Markdown

A note on whether this Julia version is known to run the notebook. Julia 1.12 is the
reference version; 1.10 depends on [`JULIA_110_STATUS`](@ref).
"""
function julia_version_check()
    v = VERSION
    if v < v"1.10"
        return callout(
            :danger,
            "Julia $v is older than 1.10, the oldest version the package supports. Install Julia 1.12 " *
            "(`juliaup add 1.12`), run `julia +1.12 notebooks/setup.jl` and choose the kernel it installs.",
        )
    elseif v < v"1.11"
        if JULIA_110_STATUS == :supported
            return callout(:ok, "Julia $v. This notebook is tested on Julia 1.10 and 1.12.")
        elseif JULIA_110_STATUS == :unsupported
            return callout(
                :warn,
                "This notebook does not run on Julia 1.10 (see `notebooks/test_notebook.jl`). You will have to " *
                "provide your own Julia 1.12 environment: `juliaup add 1.12`, then `julia +1.12 notebooks/setup.jl`, " *
                "and choose the kernel it installs.",
            )
        else
            return callout(
                :warn,
                "Julia $v. The package supports 1.10, but this notebook has not yet been verified on 1.10 " *
                "(`notebooks/test_notebook.jl` checks it). If a cell fails, provide your own Julia 1.12 " *
                "environment: `juliaup add 1.12`, then `julia +1.12 notebooks/setup.jl`.",
            )
        end
    elseif v < v"1.12"
        return callout(:note, "Julia $v. The notebook is developed on Julia 1.12; 1.11 should work as well.")
    else
        return callout(:ok, "Julia $v.")
    end
end

"`Rscript` from the `RSCRIPT` variable, the `PATH`, or the usual Windows locations; `nothing` if absent."
function find_rscript()
    r = get(ENV, "RSCRIPT", "")
    isfile(r) && return r
    r = Sys.which("Rscript")
    r !== nothing && return r
    if Sys.iswindows()
        for base in (raw"C:\Program Files\R", joinpath(homedir(), "AppData", "Local", "Programs", "R"))
            isdir(base) || continue
            for v in sort(filter(d -> startswith(d, "R-"), readdir(base)); rev=true)
                f = joinpath(base, v, "bin", "Rscript.exe")
                isfile(f) && return f
            end
        end
    end
    return nothing
end

"`true` if R can load every package the original code needs (`lhs`, `CholWishart`, `abind`, `MASS`)."
function r_packages_ok(rscript::AbstractString)
    expr = "cat(all(vapply(c('lhs','CholWishart','abind','MASS'), requireNamespace, logical(1), quietly=TRUE)))"
    try
        return strip(read(ignorestatus(`$rscript -e $expr`), String)) == "TRUE"
    catch
        return false
    end
end

"A Fortran compiler: `gfortran` on the `PATH`, or (Windows) the one in Rtools."
function find_gfortran()
    g = Sys.which("gfortran")
    g !== nothing && return g
    if Sys.iswindows()
        roots = try
            filter(d -> startswith(lowercase(d), "rtools"), readdir("C:\\"))
        catch
            String[]
        end
        for r in sort(roots; rev=true), sub in ("x86_64-w64-mingw32.static.posix", "mingw64", "usr")
            f = joinpath("C:\\", r, sub, "bin", "gfortran.exe")
            isfile(f) && return f
        end
    end
    return nothing
end

"The compiled legacy Fortran libraries in `legacy/fortran`, if both exist."
function find_compiled_fortran()
    dir = joinpath(LEGACY_DIR, "fortran")
    found = String[]
    for name in ("run_geocarb", "run_geocarb_supp")
        i = findfirst(ext -> isfile(joinpath(dir, name * ext)), (".dll", ".so", ".dylib"))
        i === nothing && return nothing
        push!(found, joinpath(dir, name * (".dll", ".so", ".dylib")[i]))
    end
    return found
end

const EXPORT_REQUIRED = (
    "constants.csv",
    "time_series.csv",
    "legacy_co2.csv",
    "legacy_o2.csv",
    "legacy_temp_plus15.csv",
    "legacy_prcout.csv",
    "legacy_windows.csv",
    "legacy_center_run.csv",
    "legacy_supp_names.txt",
    "legacy_supp_configs.csv",
)

"""
    stored_exports_info(dir = STORED_EXPORTS) -> NamedTuple

Whether an earlier run of the original R code left its exports in `dir`
(`test/legacy_comparison/output`, which git ignores), and what it says about itself.
"""
function stored_exports_info(dir::AbstractString=STORED_EXPORTS)
    ok = isdir(dir) && all(f -> isfile(joinpath(dir, f)), EXPORT_REQUIRED)
    ok || return (; available=false, dir, date="", meta=String[])
    meta = isfile(joinpath(dir, "legacy_meta.txt")) ? readlines(joinpath(dir, "legacy_meta.txt")) : String[]
    date = Libc.strftime("%Y-%m-%d %H:%M", mtime(joinpath(dir, "legacy_co2.csv")))
    return (; available=true, dir, date, meta)
end

function git_commit()
    try
        return readchomp(pipeline(`git -C $ROOT rev-parse --short HEAD`; stderr=devnull))
    catch
        return "unknown"
    end
end

"""
    detect_environment() -> NamedTuple

Everything the verification levels depend on: Julia, threads, R, R packages, Fortran
libraries or compiler, and stored R exports.
"""
function detect_environment()
    rscript = find_rscript()
    return (;
        julia=VERSION,
        threads=Threads.nthreads(),
        os=string(Sys.KERNEL, " ", Sys.ARCH),
        package=pkgversion(GeocarbPrecalibration),
        cairomakie=pkgversion(CairoMakie),
        commit=git_commit(),
        rscript,
        rpackages=rscript === nothing ? false : r_packages_ok(rscript),
        fortran_libs=find_compiled_fortran(),
        gfortran=find_gfortran(),
        exports=stored_exports_info(),
    )
end

"Level C needs R with its packages and either compiled Fortran libraries or a compiler."
function level_c_possible(env)
    return env.rscript !== nothing && env.rpackages && (env.fortran_libs !== nothing || env.gfortran !== nothing)
end

"Table of the detected environment."
function environment_table(env)
    yes(x) = x ? "✔" : "✘"
    rows = [
        ["Julia", string(env.julia), "≥ 1.10 required; 1.12 recommended"],
        ["Threads", string(env.threads), env.threads == 1 ? "precalibration runs faster with more (see setup)" : ""],
        ["Operating system", env.os, ""],
        ["GeocarbPrecalibration", string(env.package, " (commit ", env.commit, ")"), ""],
        ["CairoMakie", string(env.cairomakie), ""],
        ["Rscript", env.rscript === nothing ? "✘ not found" : _esc(env.rscript), "level C"],
        ["R packages lhs, CholWishart, abind, MASS", yes(env.rpackages), "level C"],
        [
            "Compiled legacy Fortran",
            env.fortran_libs === nothing ? "✘ not found" : _esc(join(basename.(env.fortran_libs), ", ")),
            "level C (either this or a compiler)",
        ],
        ["Fortran compiler", env.gfortran === nothing ? "✘ not found" : _esc(env.gfortran), "level C"],
        [
            "Stored R exports",
            env.exports.available ? "✔ from " * env.exports.date : "✘ none in test/legacy_comparison/output",
            "level B",
        ],
    ]
    return html_table(["", "found", "needed for"], rows; caption="This machine")
end

# ---------------------------------------------------------------------------------------
# test suite in subprocesses

const DEFAULT_GROUPS = ["unit", "io", "sampling", "constraints", "workflow", "regression", "quality", "doctests"]

_strip_ansi(s) = replace(s, r"\e\[[0-9;]*[A-Za-z]" => "")

"""
    parse_test_summary(text) -> Union{Nothing,NamedTuple}

Counts from the top row of the `Test Summary:` table that `Test` prints at the end of
a run (`Pass`, `Fail`, `Error`, `Broken`, `Total`, `Time`; absent columns are zero).
"""
function parse_test_summary(text::AbstractString)
    lines = split(_strip_ansi(text), '\n')
    i = findfirst(l -> startswith(l, "Test Summary:"), lines)
    (i === nothing || i == length(lines)) && return nothing
    header = split(strip(split(lines[i], '|'; limit=2)[end]))
    parts = split(lines[i + 1], '|'; limit=2)
    length(parts) == 2 || return nothing
    values = split(strip(parts[2]))
    length(values) == length(header) || return nothing
    d = Dict(zip(header, values))
    num(k) = something(tryparse(Int, get(d, k, "0")), 0)
    return (; pass=num("Pass"), fail=num("Fail"), error=num("Error"), broken=num("Broken"), total=num("Total"))
end

"""
    run_test_group(group; logdir) -> NamedTuple

Run `Pkg.test()` with `GROUP = group` in a fresh Julia process (as CI and
`scripts/dev/test_group.jl` do), write its output to `logdir/test_<group>.log`, and
return the counts from its summary.
"""
function run_test_group(group::AbstractString; logdir::AbstractString)
    log = joinpath(logdir, "test_$group.log")
    cmd = `$(Base.julia_cmd()) --color=no --startup-file=no --project=$ROOT -e "using Pkg; Pkg.test()"`
    cmd = addenv(cmd, "GROUP" => group)
    proc = nothing
    t = @elapsed open(log, "w") do io
        proc = run(pipeline(ignorestatus(cmd); stdout=io, stderr=io))
    end
    s = parse_test_summary(read(log, String))
    ok = proc.exitcode == 0
    status = s === nothing ? :error : (ok && s.fail == 0 && s.error == 0 ? :pass : :fail)
    return (; group, status, summary=s, seconds=t, log)
end

"Run several groups one after another, printing progress."
function run_test_groups(groups; logdir::AbstractString=mktempdir())
    results = NamedTuple[]
    for g in groups
        print("  ", rpad(g, 12), " … ")
        r = run_test_group(g; logdir)
        println(r.status == :pass ? "passed" : uppercase(string(r.status)), @sprintf(" (%.0f s)", r.seconds))
        push!(results, r)
    end
    return results
end

function test_results_table(results)
    rows = map(results) do r
        s = r.summary
        c(k) = s === nothing ? "–" : string(getfield(s, k))
        return [
            r.group,
            BADGE[r.status],
            c(:pass),
            c(:fail),
            c(:error),
            c(:broken),
            c(:total),
            @sprintf("%.0f s", r.seconds),
        ]
    end
    return html_table(
        ["group", "result", "pass", "fail", "error", "broken", "total", "wall time"],
        rows;
        caption="Test groups, each run with Pkg.test() in its own process",
    )
end

function plot_test_results(results)
    n = length(results)
    passes = [r.summary === nothing ? 0 : r.summary.pass for r in results]
    bad = [r.summary === nothing ? 1 : r.summary.fail + r.summary.error for r in results]
    fig = Figure(; size=(900, 90 + 32 * n))
    ax1 = Axis(
        fig[1, 1];
        yticks=(1:n, [r.group for r in results]),
        yreversed=true,
        xlabel="tests passed",
        title="Passing tests per group",
    )
    barplot!(ax1, 1:n, passes; direction=:x, color=[b == 0 ? PALETTE.julia : PALETTE.fail for b in bad])
    ax2 = Axis(fig[1, 2]; yticks=(1:n, fill("", n)), yreversed=true, xlabel="seconds", title="Wall time")
    barplot!(ax2, 1:n, [r.seconds for r in results]; direction=:x, color=PALETTE.legacy)
    colsize!(fig.layout, 2, Relative(0.3))
    return fig
end

# ---------------------------------------------------------------------------------------
# the repository's comparison code

"""
    load_repo_file(path) -> Module

Include a repository file into a fresh module (so re-running a cell never clashes
with an earlier definition) and return the module.
"""
function load_repo_file(path::AbstractString)
    name = Symbol("Repo_", splitext(basename(path))[1], "_", time_ns())
    Core.eval(Main, Expr(:module, true, name, Expr(:block, :(include($(abspath(path)))))))
    return getfield(Main, name)
end

const _COMPARE = Ref{Union{Module,Nothing}}(nothing)
const _PLOTS = Ref{Union{Module,Nothing}}(nothing)

"`test/legacy_comparison/compare.jl`, loaded once."
function compare_module()
    _COMPARE[] === nothing && (_COMPARE[] = load_repo_file(joinpath(COMPARISON_DIR, "compare.jl")))
    return _COMPARE[]
end

"`test/legacy_comparison/plot_comparison.jl`, loaded once."
function plot_module()
    _PLOTS[] === nothing && (_PLOTS[] = load_repo_file(joinpath(COMPARISON_DIR, "plot_comparison.jl")))
    return _PLOTS[]
end

"The tolerances in `test/tolerances.toml`, the single source shared by both Fortran tests."
function read_tolerances()
    t = TOML.parsefile(joinpath(ROOT, "test", "tolerances.toml"))
    return (; rtol_clean=Float64(t["rtol_clean"]), rtol_post=Float64(t["rtol_post"]), atol=Float64(t["atol"]))
end

"One row per check, the same shape for every level."
function as_check(s)
    region = if occursin("[before any failure]", s.label)
        :before
    elseif occursin("[at/after a failure]", s.label)
        :after
    elseif isnan(s.rtol)
        :mask
    else
        :other
    end
    return (;
        label=s.label,
        region,
        n=s.n,
        max_rel=s.max_rel,
        rtol=s.rtol,
        mismatches=s.mask_mismatch,
        n_bad=s.n_bad,
        passed=s.mask_mismatch == 0 && s.n_bad == 0,
    )
end

const GOLDEN_VARIANTS = [
    ("control", (130, 80), 1.0, false),
    ("gym", (130, 80), 0.25, false),
    ("timing", (110, 60), 1.0, false),
    ("gym_timing", (110, 60), 0.25, false),
    ("dT2X", (130, 80), 1.0, true),
    ("gym_timing_dT2X", (110, 60), 0.25, true),
]

"""
    golden_master_checks(; tol = read_tolerances()) -> Vector

Level A with numbers: run Julia on the inputs stored in `test/fixtures/fortran` and
compare with the stored Fortran outputs exactly as `test/regression/test_fortran_golden.jl`
does, but keep the statistics (largest relative difference per quantity and region)
instead of only pass/fail. The statistics come from `diffstats`/`maskstats` of
`compare.jl`.
"""
function golden_master_checks(; tol=read_tolerances())
    C = compare_module()
    labels = sort([replace(f, "_inputs.csv" => "") for f in readdir(FIXTURE_DIR) if endswith(f, "_inputs.csv")])
    age = collect(570.0:-10.0:0.0)
    nt = length(age)
    steps = ["step_$k" for k in 1:nt]
    checks = NamedTuple[]
    for label in labels
        t = read_csv_table(joinpath(FIXTURE_DIR, "$(label)_inputs.csv"))
        single = label != "real8"
        cases = map(t.rows) do row
            num(name) = GP.parse_number(row[findfirst(==(name), t.header)])
            p = ConstantParams(collect(CONSTANT_PARAMETER_NAMES), [num(String(n)) for n in CONSTANT_PARAMETER_NAMES])
            d = Dict{Symbol,Vector{Float64}}(n => [num("$(n)_$k") for k in 1:nt] for n in TIME_FORCING_NAMES)
            return (p, TimeForcings(age, d; check_finite=false), Int(num("iteration_threshold")))
        end
        variants = Tuple{String,Function}[(
            "main", thr -> ModelOptions(; fortran_single_literals=single, iteration_threshold=thr)
        )]
        for (nm, ramp_ages, g, ramp) in GOLDEN_VARIANTS
            isfile(joinpath(FIXTURE_DIR, "$(label)_supp_$(nm)_co2.csv")) || continue
            mk =
                thr -> ModelOptions(;
                    gym_angio_transition=ramp_ages,
                    gym_factor=g,
                    dT2X_ramp=ramp,
                    fortran_single_literals=single,
                    iteration_threshold=thr,
                )
            push!(variants, ("supp_$nm", mk))
        end
        for (name, mk) in variants
            ref = Dict{String,Matrix{Float64}}()
            for q in ("co2", "o2", "temp15")
                tq = read_csv_table(joinpath(FIXTURE_DIR, "$(label)_$(name)_$(q).csv"))
                ref[q] = reduce(hcat, [GP.numeric_column(tq, s; allow_missing=true) for s in steps])
            end
            n = size(ref["co2"], 1)
            jl = Dict(q => Matrix{Float64}(undef, n, nt) for q in ("co2", "o2", "temp15"))
            for i in 1:n
                p, f, thr = cases[i]
                r = run_geocarb(p, f; options=mk(thr))
                jl["co2"][i, :] .= r.co2
                jl["o2"][i, :] .= r.o2
                jl["temp15"][i, :] .= r.temp .+ 15
            end
            post = cumsum(isinf.(ref["co2"]); dims=2) .> 0
            for (q, qname) in (("co2", "CO2"), ("o2", "O2"), ("temp15", "temperature + 15"))
                J, R = jl[q], ref[q]
                lab = "$label $name $qname"
                push!(checks, as_check(Base.invokelatest(C.maskstats, "$lab: pass/fail (Inf/NaN) positions", J, R)))
                b = Base.invokelatest(
                    C.diffstats, "$lab [before any failure]", J[.!post], R[.!post]; rtol=tol.rtol_clean, atol=tol.atol
                )
                a = Base.invokelatest(
                    C.diffstats, "$lab [at/after a failure]", J[post], R[post]; rtol=tol.rtol_post, atol=tol.atol
                )
                push!(checks, as_check(b), as_check(a))
            end
        end
    end
    return checks
end

"Files written by `run_legacy.R` (inputs and outputs of the original code)."
function export_files(dir::AbstractString)
    keep(f) =
        (startswith(f, "legacy_") && (endswith(f, ".csv") || endswith(f, ".txt"))) ||
        f in ("constants.csv", "time_series.csv")
    return filter(keep, readdir(dir))
end

"""
    run_comparison(dir) -> NamedTuple

Run `compare_with_legacy` of `compare.jl` on the R exports in `dir`, inside a test
set, with its long printed report sent to `dir/compare_stdout.txt`. `dir` must be a
scratch folder: `compare_with_legacy` writes its report, statistics and Julia outputs
there.
"""
function run_comparison(dir::AbstractString; fortran_dir::AbstractString=joinpath(LEGACY_DIR, "fortran"))
    C = compare_module()
    stats = Ref{Any}(nothing)
    err = Ref{Any}(nothing)
    log = joinpath(dir, "compare_stdout.txt")
    t = @elapsed open(log, "w") do io
        redirect_stdout(io) do
            try
                @testset "Julia port vs original R/Fortran" begin
                    stats[] = Base.invokelatest(C.compare_with_legacy, dir; fortran_dir=fortran_dir)
                end
            catch e
                err[] = e
            end
        end
    end
    checks = stats[] === nothing ? NamedTuple[] : [as_check(s) for s in stats[]]
    return (; dir, checks, error=err[], seconds=t, report=joinpath(dir, "comparison_report.txt"), log)
end

"""
    replay_stored_exports(; workdir = mktempdir()) -> NamedTuple

Level B: copy the stored R exports into a scratch folder and compare there, so the
files in `test/legacy_comparison/output` are never overwritten.
"""
function replay_stored_exports(; workdir::AbstractString=mktempdir())
    for f in export_files(STORED_EXPORTS)
        cp(joinpath(STORED_EXPORTS, f), joinpath(workdir, f); force=true)
    end
    return run_comparison(workdir)
end

"""
    run_live_legacy(env; workdir = mktempdir(), n = 1000, n_supp = 200, seed = 2026) -> NamedTuple

Level C: run the unmodified R/Fortran code with `test/legacy_comparison/run_legacy.R`
into a scratch folder, then compare. The R step may compile the Fortran in
`legacy/fortran` (with `R CMD SHLIB`) if no compiled library is there yet.
"""
function run_live_legacy(
    env; workdir::AbstractString=mktempdir(), n::Integer=1000, n_supp::Integer=200, seed::Integer=2026
)
    script = joinpath(COMPARISON_DIR, "run_legacy.R")
    cmd = `$(env.rscript) $script $LEGACY_DIR $workdir $n $n_supp $seed`
    rlog = joinpath(workdir, "run_legacy_R.log")
    proc = nothing
    t = @elapsed open(rlog, "w") do io
        proc = run(pipeline(ignorestatus(cmd); stdout=io, stderr=io))
    end
    if proc.exitcode != 0
        return (;
            dir=workdir,
            checks=NamedTuple[],
            error="R exited with code $(proc.exitcode); see $rlog",
            seconds=t,
            report="",
            log=rlog,
            r_seconds=t,
        )
    end
    res = run_comparison(workdir)
    return merge(res, (; r_seconds=t, r_log=rlog))
end

# ---------------------------------------------------------------------------------------
# presenting the checks

"Short label for a check in a figure (the region is shown by the panel)."
short_label(s) = replace(s, " [before any failure]" => "", " [at/after a failure]" => "")

"""
    plot_headroom(checks; title) -> Figure

For every value check: the largest relative difference found (dot) against the
tolerance (dashed line), separately before and at/after a run's first failed step.
The shaded zone right of the line is where a check would fail; the distance from the
dot to the line is the headroom.
"""
function plot_headroom(checks; title::AbstractString="")
    panels = [
        (:before, "Before a run's first failed step", PALETTE.julia),
        (:after, "At or after the first failed step", PALETTE.post),
    ]
    nmax = maximum(r -> count(c -> c.region == r, checks), first.(panels))
    fig = Figure(; size=(1150, 170 + 17 * nmax))
    isempty(title) || Label(fig[0, 1:2], title; font=:bold, fontsize=16, halign=:left)
    for (k, (region, name, col)) in enumerate(panels)
        cs = filter(c -> c.region == region, checks)
        isempty(cs) && continue
        tol = maximum(c -> c.rtol, cs)
        worst = maximum(c -> c.max_rel, cs)
        ax = Axis(
            fig[1, k];
            xscale=log10,
            yreversed=true,
            title=name,
            subtitle=@sprintf("limit %.0e · worst %.1e · headroom ×%.0f", tol, worst, worst > 0 ? tol / worst : Inf),
            yticks=(1:length(cs), short_label.([c.label for c in cs])),
            yticklabelsize=10,
            xlabel="largest relative difference (0 drawn at 1e-18)",
        )
        vspan!(ax, [tol], [1.0]; color=(PALETTE.fail, 0.08))
        vlines!(ax, [tol]; color=PALETTE.fail, linestyle=:dash, linewidth=1.5)
        x = [max(c.max_rel, 1e-18) for c in cs]
        ok = [c.passed for c in cs]
        y = collect(1:length(cs))
        scatter!(ax, x[ok], y[ok]; color=col, markersize=9, strokecolor=:white, strokewidth=1)
        any(.!ok) && scatter!(ax, x[.!ok], y[.!ok]; color=PALETTE.fail, marker=:xcross, markersize=13)
        xlims!(ax, 3e-19, 1.0)
    end
    return fig
end

"Numbers for the verdict of one level."
function summarize_checks(checks)
    isempty(checks) && return nothing
    before = filter(c -> c.region == :before, checks)
    after = filter(c -> c.region == :after, checks)
    masks = filter(c -> c.region == :mask, checks)
    return (;
        n=length(checks),
        passed=count(c -> c.passed, checks),
        worst_before=isempty(before) ? 0.0 : maximum(c -> c.max_rel, before),
        worst_after=isempty(after) ? 0.0 : maximum(c -> c.max_rel, after),
        mask_mismatches=sum(c -> c.mismatches, masks; init=0),
        n_masks=length(masks),
    )
end

function checks_table(checks; collapsed=nothing)
    rows = [
        [
            _esc(c.label),
            string(c.n),
            fmt(c.max_rel),
            isnan(c.rtol) ? "identical" : fmt(c.rtol),
            string(c.mismatches),
            string(c.n_bad),
            badge(c.passed),
        ] for c in checks
    ]
    return html_table(
        ["check", "cells", "largest rel. difference", "tolerance", "Inf/NaN mismatches", "out of tolerance", ""],
        rows;
        collapsed,
    )
end

function verdict_table(levels)
    tol = read_tolerances()
    rows = map(levels) do (name, what, s)
        if s === nothing
            [name, what, BADGE[:skip], "–", "–", "–"]
        else
            [
                name,
                what,
                badge(s.passed == s.n),
                "$(s.passed) / $(s.n)",
                fmt(s.worst_before) * " (limit " * fmt(tol.rtol_clean) * ")",
                fmt(s.worst_after) * " (limit " * fmt(tol.rtol_post) * ")",
            ]
        end
    end
    return html_table(
        ["level", "compared against", "result", "checks passed", "worst before a failure", "worst at/after a failure"],
        rows;
        caption="Verdict",
    )
end

# ---------------------------------------------------------------------------------------
# Part 1: introducing the model

const PRIOR_FILE = datapath("GEOCARB_input_summaries_calib_all.csv")
const ARRAY_FILE = datapath("GEOCARB_input_arrays_NewDegassing.csv")
const PROXY_FILE = datapath("CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv")
const TEMP_FILE = datapath("Mills_GR_2019_temp_co2.csv")

"Table of the calibrated constant parameters and their priors."
function prior_table_html(table)
    specs = filter(s -> s.calibrate, GP.constant_specs(table))
    rows = [
        [
            "<code>$(s.name)</code>",
            string(s.distribution),
            @sprintf("%.4g", s.mean),
            @sprintf("%.4g", s.two_sigma),
            @sprintf("[%.4g, %.4g]", s.lower, s.upper),
            _esc(parameter_units(s.name)),
            _esc(parameter_description(s.name)),
        ] for s in specs
    ]
    return html_table(
        ["parameter", "prior", "mean", "2σ", "bounds", "units", "meaning"],
        rows;
        collapsed="The $(length(specs)) calibrated constant parameters and their priors (click to expand)",
    )
end

"The 12 forcings: centre ± 1σ over time."
function plot_forcings(tprior)
    x = -tprior.center.age
    fig = Figure(; size=(1100, 820))
    for (j, nm) in enumerate(TIME_FORCING_NAMES)
        r, c = divrem(j - 1, 3)
        ax = Axis(
            fig[r + 1, c + 1]; title=String(nm), ylabel=parameter_units(nm), xlabel=r == 3 ? "Time [Myr ago]" : ""
        )
        μ = getfield(tprior.center, nm)
        σ = getfield(tprior.sigma, nm)
        band!(ax, x, μ .- σ, μ .+ σ; color=(PALETTE.julia, 0.25))
        lines!(ax, x, μ; color=PALETTE.julia, linewidth=2)
    end
    Label(fig[0, 1:3], "Time-varying forcings: centre (line) ± 1σ (band)"; font=:bold, fontsize=16, halign=:left)
    return fig
end

"""
    plot_runs(runs; cw = nothing, tw = nothing) -> Figure

CO2, O2 and temperature (`temperature(r)`, i.e. `temp + 15 °C`, the quantity that
precalibration compares with the temperature windows) for several runs, given as
`label => result` pairs. Failed steps are left out of the lines and marked with
crosses at the bottom of the CO2 panel.
"""
function plot_runs(runs; cw=nothing, tw=nothing, colors=nothing)
    cols = colors === nothing ? MK.wong_colors() : colors
    fig = Figure(; size=(1000, 820))
    ax1 = Axis(fig[1, 1]; ylabel="CO₂ [ppmv]", yscale=log10, title="Atmospheric CO₂")
    ax2 = Axis(fig[2, 1]; ylabel="O₂ [%]", title="Atmospheric O₂")
    ax3 = Axis(fig[3, 1]; ylabel="T [°C]", xlabel="Time [Myr ago]", title="Global mean temperature (temp + 15 °C)")
    if cw !== nothing
        ok = cw.low .> 0
        band!(ax1, -cw.age[ok], cw.low[ok], cw.high[ok]; color=(PALETTE.legacy, 0.15), label="CO₂ windows")
    end
    tw === nothing || band!(ax3, -tw.age, tw.low, tw.high; color=(PALETTE.legacy, 0.15), label="temperature windows")
    for (k, (lab, r)) in enumerate(runs)
        c = cols[mod1(k, length(cols))]
        x = -r.age
        co2 = finite_or_nan(r.co2)
        lines!(ax1, x, [v > 0 ? v : NaN for v in co2]; color=c, linewidth=2, label=lab)
        lines!(ax2, x, finite_or_nan(r.o2); color=c, linewidth=2)
        lines!(ax3, x, finite_or_nan(temperature(r)); color=c, linewidth=2)
        bad = findall(s -> s != Converged, r.status)
        isempty(bad) || scatter!(ax1, x[bad], fill(160.0, length(bad)); color=c, marker=:xcross, markersize=10)
    end
    linkxaxes!(ax1, ax2, ax3)
    axislegend(ax1; position=:rt, labelsize=11)
    return fig
end

"""
    prior_draws(n; seed = 2024) -> Vector{Tuple{ConstantParams,TimeForcings}}

`n` random inputs drawn from the priors (constants by Latin hypercube, forcings by
the inverse-Wishart sampler), as `test/testutils.jl` does.
"""
function prior_draws(n::Integer; seed::Integer=2024)
    table = read_prior_table(PRIOR_FILE)
    tprior = read_time_arrays(ARRAY_FILE)
    rng = GP.StableRNG(seed)
    priors = build_priors(table)
    X = sample_constants(rng, priors, n)
    names = [p.name for p in priors]
    base = parameter_vector(mean_constants(table))
    sampler = InverseWishartSampler(tprior)
    out = Tuple{ConstantParams{Float64},TimeForcings{Float64}}[]
    for i in 1:n
        v = copy(base)
        for (j, nm) in enumerate(names)
            v[findfirst(==(nm), CONSTANT_PARAMETER_NAMES)] = X[i, j]
        end
        f = copy(tprior.center)
        sample_time_forcings!(rng, f, sampler)
        push!(out, (ConstantParams(collect(CONSTANT_PARAMETER_NAMES), v), f))
    end
    return out
end

const STATUS_COLORS = Dict(
    Converged => PALETTE.julia,
    NotConverged => PALETTE.post,
    NaNEncountered => PALETTE.fail,
    RCO2OutOfRange => PALETTE.f64,
    PresentDayCheckFailed => PALETTE.gold,
    InvalidState => PALETTE.legacy,
)

"Stacked bars: how many of `results` have each step status at each age."
function plot_step_status(results; title::AbstractString="")
    age = first(results).age
    nt = length(age)
    statuses = collect(instances(StepStatus))
    counts = [count(r -> r.status[j] == s, results) for j in 1:nt, s in statuses]
    x = repeat(-age, length(statuses))
    grp = repeat(1:length(statuses); inner=nt)
    fig = Figure(; size=(1000, 430))
    ax = Axis(fig[1, 1]; xlabel="Time [Myr ago]", ylabel="runs", title=title)
    barplot!(ax, x, vec(counts); stack=grp, color=[STATUS_COLORS[statuses[g]] for g in grp], gap=0.1, width=9)
    Legend(fig[1, 2], [PolyElement(; color=STATUS_COLORS[s]) for s in statuses], string.(statuses), "step status")
    return fig
end

"Climate sensitivity summary of a precalibration result as a table."
function sensitivity_table(res)
    s = climate_sensitivity_summary(res)
    p = s.probs
    row(name, q) = [name; [@sprintf("%.2f", v) for v in q]]
    rows = [row("ΔT2x [°C]", s.deltaT2X), row("GLAC [–]", s.GLAC), row("ΔT2x·GLAC (glacial) [°C]", s.deltaT2X_glacial)]
    tbl = html_table(
        ["", [@sprintf("%g %%", 100 * x) for x in p]...], rows; caption="Quantiles over $(s.n) accepted samples"
    )
    ex = join([@sprintf("Pr(ΔT2x ≥ %g °C) = %.3f", k, v) for (k, v) in sort(collect(s.prob_exceed))], "; ")
    return tbl, ex
end

"""
    plot_carbon_cycle_schematic() -> Figure

A sketch of the long-term carbon budget that GEOCARB keeps (not a model output).
"""
function plot_carbon_cycle_schematic()
    fig = Figure(; size=(1000, 540))
    ax = Axis(fig[1, 1])
    hidedecorations!(ax)
    hidespines!(ax)
    limits!(ax, 0, 1, 0, 1.05)
    function box(x, y, w, h, title, sub, col)
        poly!(ax, Rect(x, y, w, h); color=(col, 0.12), strokecolor=col, strokewidth=1.5)
        text!(ax, x + w / 2, y + 0.64h; text=title, align=(:center, :center), fontsize=15, font=:bold)
        text!(ax, x + w / 2, y + 0.3h; text=sub, align=(:center, :center), fontsize=11, color=PALETTE.legacy)
        return nothing
    end
    function arrow(p, q, label, col; offset=(0.0, 0.0), align=(:center, :center))
        lines!(ax, [p[1], q[1]], [p[2], q[2]]; color=col, linewidth=2.5)
        θ = atan(q[2] - p[2], q[1] - p[1])
        scatter!(ax, [q[1]], [q[2]]; marker=:utriangle, rotation=θ - π / 2, markersize=16, color=col)
        text!(
            ax,
            (p[1] + q[1]) / 2 + offset[1],
            (p[2] + q[2]) / 2 + offset[2];
            text=label,
            align=align,
            fontsize=11,
            color=col,
        )
        return nothing
    end
    box(0.36, 0.70, 0.28, 0.20, "Atmosphere + ocean", "CO₂ (solved each step), O₂", PALETTE.julia)
    box(0.02, 0.06, 0.27, 0.20, "Carbonate rocks", "Ca and Mg carbonates", PALETTE.legacy)
    box(0.365, 0.06, 0.27, 0.20, "Mantle and crust", "volcanism, metamorphism", PALETTE.post)
    box(0.71, 0.06, 0.27, 0.20, "Organic carbon", "buried in sediments", PALETTE.ok)
    arrow(
        (0.40, 0.70),
        (0.24, 0.26),
        "silicate weathering\n→ carbonate burial\n(removes CO₂)",
        PALETTE.julia;
        offset=(0.02, 0.02),
        align=(:left, :center),
    )
    arrow(
        (0.08, 0.26),
        (0.36, 0.76),
        "carbonate\nweathering",
        PALETTE.legacy;
        offset=(-0.06, 0.04),
        align=(:right, :center),
    )
    arrow((0.50, 0.26), (0.50, 0.70), "degassing\n(fSR, fC)", PALETTE.post; offset=(0.015, 0.0), align=(:left, :center))
    arrow((0.60, 0.70), (0.76, 0.26), "organic\nburial", PALETTE.ok; offset=(-0.02, 0.02), align=(:right, :center))
    arrow((0.92, 0.26), (0.64, 0.76), "organic\nweathering", PALETTE.ok; offset=(0.06, 0.04), align=(:left, :center))
    text!(
        ax,
        0.5,
        1.0;
        text="Thermostat: higher CO₂ → warmer (ΔT2x) → faster silicate weathering (ACT, plants, runoff, relief) → less CO₂",
        align=(:center, :center),
        fontsize=13,
        font=:italic,
    )
    return fig
end

"""
    plot_literal_effect(single, double) -> Figure

Relative difference of CO₂ between runs with single-precision literals (`single`,
the default) and Float64 literals (`double`), over steps before either run's first
failure, and the number of runs whose pass/fail outcome changes.
"""
function plot_literal_effect(single, double)
    rel = Float64[]
    flips = 0
    for (a, b) in zip(single, double)
        flips += succeeded(a) != succeeded(b)
        stop = min(
            something(findfirst(!isfinite, a.co2), length(a.co2) + 1),
            something(findfirst(!isfinite, b.co2), length(b.co2) + 1),
        )
        for j in 1:(stop - 1)
            x, y = a.co2[j], b.co2[j]
            push!(rel, log10(max(abs(x - y) / max(abs(x), abs(y)), 1e-18)))
        end
    end
    fig = Figure(; size=(950, 420))
    ax = Axis(
        fig[1, 1];
        title="CO₂ with Float64 literals against the default (single-precision literals)",
        subtitle="$flips of $(length(single)) runs change between pass and fail; histogram of valid steps before any failure",
        xlabel="log₁₀ relative difference (−18 = identical)",
        ylabel="steps",
    )
    hist!(ax, rel; bins=-18.125:0.25:0.125, color=(PALETTE.f64, 0.7))
    return fig
end

"""
    levels_table(env, run_b, run_c) -> HTML

What each verification level compares against, what it needs, what it proves and
does not prove, and whether it runs on this machine.
"""
function levels_table(env, run_b, run_c)
    b_status = if !run_b
        BADGE[:skip] * " (switched off in Settings)"
    elseif env.exports.available
        "will run (exports from " * env.exports.date * ")"
    else
        BADGE[:skip] * " (no stored exports on this machine)"
    end
    c_status = if run_c === false
        BADGE[:skip] * " (switched off in Settings)"
    elseif run_c === true || level_c_possible(env)
        "will run"
    else
        BADGE[:skip] * " (needs R with its packages and a Fortran compiler; see Setup)"
    end
    rows = [
        [
            "<b>A</b> golden master",
            "stored output of the compiled original Fortran (<code>test/fixtures/fortran</code>): 100 prior samples, main model and 6 supplemental variants",
            "Julia only",
            "the Julia model reproduces the Fortran model at every step, on this machine and Julia version",
            "the input pipeline, priors, windows or % outbound; inputs other than those 100 samples",
            "will run",
        ],
        [
            "<b>B</b> replay",
            "inputs and outputs saved by an earlier run of the unmodified R/Fortran code (<code>test/legacy_comparison/output</code>, 1000 samples)",
            "an earlier level-C run on this machine (the folder is not in git)",
            "the whole Julia pipeline (input processing, prior transform, model, % outbound, supplemental variants) reproduces what the original code produced then",
            "that the original code still runs, or runs the same way, here and now",
            b_status,
        ],
        [
            "<b>C</b> live",
            "the unmodified R/Fortran code in <code>legacy/</code>, run now",
            "R ≥ 4.1 with lhs, CholWishart, abind, MASS; a Fortran compiler or compiled libraries",
            "everything level B proves, against output produced now on this machine; also that R passed the inputs to the Fortran unchanged (direct <code>ccall</code>, bit for bit)",
            "other operating systems (CI's Legacy workflow runs it on Linux)",
            c_status,
        ],
    ]
    return html_table(["level", "compares Julia against", "needs", "verifies", "does not verify", "here"], rows)
end

"""
    level_status(res, level, env, setting) -> Markdown

One paragraph on what happened at level `:B` or `:C`: skipped and why, failed to run,
or the outcome.
"""
function level_status(res, level::Symbol, env, setting)
    if res === nothing
        if setting === false
            return callout(:note, "Level $level skipped: switched off in *Settings*.")
        elseif level == :B
            return callout(
                :note,
                "Level B skipped: this machine has no stored exports in `test/legacy_comparison/output` " *
                "(the folder is not in git). Run level C once, or `julia --project=. test/legacy_comparison/run_comparison.jl`, " *
                "to create them.",
            )
        else
            missing_parts = String[]
            env.rscript === nothing && push!(missing_parts, "R (`Rscript`)")
            env.rscript !== nothing &&
                !env.rpackages &&
                push!(missing_parts, "the R packages lhs, CholWishart, abind, MASS")
            env.fortran_libs === nothing &&
                env.gfortran === nothing &&
                push!(missing_parts, "a Fortran compiler (gfortran; Rtools on Windows)")
            return callout(
                :warn,
                "Level C skipped: it needs " *
                join(missing_parts, ", ", " and ") *
                ". See *Setup* for how to install them, then re-run this cell (or set `RUN_LEVEL_C = true`).",
            )
        end
    end
    if isempty(res.checks)
        return callout(:danger, "Level $level did not complete: $(res.error). Logs: `$(res.log)`.")
    end
    s = summarize_checks(res.checks)
    meta = if level == :B && !isempty(env.exports.meta)
        " The exports were made with: " *
        join(filter(l -> occursin(r"^(R|seed|n_sample|n_supp):", l), env.exports.meta), "; ") *
        "."
    else
        ""
    end
    if s.passed == s.n
        return callout(
            :ok,
            "**Level $level: all $(s.n) checks pass** in $(round(Int, res.seconds)) s. Pass/fail positions identical in all " *
            "$(s.n_masks) position checks; largest relative difference $(fmt(s.worst_before)) before a failure and " *
            "$(fmt(s.worst_after)) at or after one.$meta Report: `$(res.report)`.",
        )
    end
    return callout(
        :danger,
        "**Level $level: $(s.n - s.passed) of $(s.n) checks fail.** See the table below and `$(res.report)`.$meta",
    )
end

"Headroom figure of a level, or a note when the level was skipped or did not complete."
function level_headroom(res, title::AbstractString)
    res === nothing && return callout(:note, "Skipped (see above).")
    isempty(res.checks) && return callout(:note, "No results (see above).")
    return plot_headroom(res.checks; title)
end

"Collapsed table of every check of a level, or a note when skipped."
function level_checks_table(res, name::AbstractString)
    (res === nothing || isempty(res.checks)) && return callout(:note, "Skipped (see above).")
    return checks_table(res.checks; collapsed="All $(length(res.checks)) $name checks (click to expand)")
end

const _LOADED_COMPARISONS = Dict{String,Any}()

"""
    comparison_figure(res, name) -> Figure or Markdown

Figure `name` (for example `:fig_centre_run`) of `plot_comparison.jl`, drawn from the
results of level B or C; a note if that level did not run.
"""
function comparison_figure(res, name::Symbol)
    (res === nothing || isempty(res.checks)) && return callout(:note, "Skipped (this level did not run).")
    P = plot_module()
    c = get!(() -> Base.invokelatest(P.load_comparison, res.dir), _LOADED_COMPARISONS, res.dir)
    fig = Base.invokelatest(getfield(P, name), c)
    return fig === nothing ? callout(:note, "Not available for this run.") : fig
end

"""
    overall_verdict(test_results, golden, resB, resC) -> Markdown

The conclusion, computed from the results above.
"""
function overall_verdict(test_results, golden, resB, resC)
    tests_ok = all(r -> r.status == :pass, test_results)
    levels = [
        ("A", summarize_checks(golden)),
        ("B", resB === nothing ? nothing : summarize_checks(resB.checks)),
        ("C", resC === nothing ? nothing : summarize_checks(resC.checks)),
    ]
    ran = filter(l -> l[2] !== nothing, levels)
    levels_ok = all(l -> l[2].passed == l[2].n, ran)
    skipped = [l[1] for l in levels if l[2] === nothing]
    groups = join([r.group for r in test_results], ", ")
    note = if isempty(skipped)
        ""
    else
        " Level(s) " * join(skipped, " and ") * " did not run on this machine (see 2.5 and 2.6)."
    end
    if tests_ok && levels_ok
        return callout(
            :ok,
            "**Verified on this machine.** The test groups ($groups) pass, and the Julia port agrees with the original " *
            "R/Fortran code within `test/tolerances.toml` at level(s) " *
            join(first.(ran), ", ") *
            ": the same steps fail, " *
            "% outbound is identical, and values agree to rounding error.$note",
        )
    end
    bad = String[]
    tests_ok || push!(bad, "test groups " * join([r.group for r in test_results if r.status != :pass], ", "))
    for (l, s) in ran
        s.passed == s.n || push!(bad, "level $l ($(s.n - s.passed) checks)")
    end
    return callout(:danger, "**Not verified:** failures in " * join(bad, "; ") * ". See the tables above.$note")
end
