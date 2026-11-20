#!/usr/bin/env julia
#
# Compare the Julia port with the ORIGINAL R/Fortran code, end to end.
#
#   julia --project=. test/legacy_comparison/run_comparison.jl [options]
#
# Options (all optional):
#   --legacy-dir DIR   folder with the original R/, fortran/, input_data/   (default: legacy/,
#                      or the environment variable GEOCARB_LEGACY_DIR)
#   --out DIR          where the R exports and the report go (default: test/legacy_comparison/output)
#   --n N              samples drawn by the R code (default 1000)
#   --n-supp N         samples re-run for each supplemental variant (default 200)
#   --seed S           R random seed (default 2026)
#   --rtol-clean X     tolerance before a run's first failed step (default 1e-8)
#   --rtol-post X      tolerance at/after a run's first failed step (default 1e-4)
#   --atol X           absolute tolerance (default 1e-10)
#                      The defaults are read from test/tolerances.toml. CI and the
#                      pre-push hook never pass these three options.
#   --worst N          worst cells listed per region in the report (default 10)
#   --skip-r           reuse the exports already in --out (do not run R again)
#   --rscript PATH     Rscript executable (default: the RSCRIPT environment variable,
#                      Rscript on the PATH, or the newest C:\Program Files\R\R-*\bin\Rscript.exe)
#   --no-plots         do not draw the figures (plot_comparison.jl; drawn into --out/figures
#                      whenever CairoMakie can be loaded)
#
# Typical run time: under a minute for R and under two minutes for Julia (mostly
# compilation). Also run by `GROUP=legacy julia --project=. -e "using Pkg; Pkg.test()"`.

using Test
using GeocarbPrecalibration

include(joinpath(@__DIR__, "compare.jl"))

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

function comparison_options(args)
    root = normpath(joinpath(@__DIR__, "..", ".."))
    o = Dict{String,Any}(
        "legacy-dir" => get(ENV, "GEOCARB_LEGACY_DIR", joinpath(root, "legacy")),
        "out" => joinpath(@__DIR__, "output"),
        "n" => "1000",
        "n-supp" => "200",
        "seed" => "2026",
        "rtol-clean" => string(RTOL_CLEAN),
        "rtol-post" => string(RTOL_POST),
        "atol" => string(ATOL),
        "worst" => "10",
        "skip-r" => false,
        "rscript" => nothing,
        "no-plots" => false,
    )
    i = 1
    while i <= length(args)
        a = args[i]
        startswith(a, "--") || error("unexpected argument $a")
        k = a[3:end]
        haskey(o, k) || error("unknown option $a")
        if k in ("skip-r", "no-plots")
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

function run_legacy_comparison(args=String[])
    o = comparison_options(args)
    legacy = abspath(o["legacy-dir"])
    out = abspath(o["out"])
    for sub in ("R", "fortran", "input_data")
        isdir(joinpath(legacy, sub)) || error("$legacy does not look like the original repository (missing $sub/)")
    end
    if !o["skip-r"]
        rscript = find_rscript(o["rscript"])
        mkpath(out)
        cmd = `$rscript $(joinpath(@__DIR__, "run_legacy.R")) $legacy $out $(o["n"]) $(o["n-supp"]) $(o["seed"])`
        println("Running the original R/Fortran code:\n  ", cmd)
        t = @elapsed run(cmd)
        println("  done in ", round(t; digits=1), " s")
    end
    t = @elapsed @testset "Julia port vs original R/Fortran" begin
        compare_with_legacy(
            out;
            rtol_clean=parse(Float64, o["rtol-clean"]),
            rtol_post=parse(Float64, o["rtol-post"]),
            atol=parse(Float64, o["atol"]),
            worst=parse(Int, o["worst"]),
            fortran_dir=joinpath(legacy, "fortran"),
        )
    end
    println("Julia comparison finished in ", round(t; digits=1), " s; report: ", joinpath(out, "comparison_report.txt"))
    return o["no-plots"] || draw_comparison_figures(out)
end

"""
    draw_comparison_figures(out)

Draw the figures of `plot_comparison.jl` into `out/figures` if CairoMakie can be
loaded; otherwise say how to install it. Never fails the comparison.
"""
function draw_comparison_figures(out::AbstractString)
    try
        @eval Main using CairoMakie
    catch
        println("Figures skipped: CairoMakie is not installed (julia -e \"using Pkg; Pkg.add(\\\"CairoMakie\\\")\").")
        return String[]
    end
    try
        Base.include(Main, joinpath(@__DIR__, "plot_comparison.jl"))
        println("Drawing the comparison figures:")
        return Base.invokelatest(Main.plot_legacy_comparison, out)
    catch err
        @warn "drawing the comparison figures failed" exception = (err, catch_backtrace())
        return String[]
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_legacy_comparison(ARGS)
else
    run_legacy_comparison(String[])
end
