# Test entry point. Select a group with the GROUP environment variable:
#
#   GROUP=all (default)  unit, io, sampling, constraints, workflow, regression, quality, doctests
#   GROUP=unit | io | sampling | constraints | workflow | regression | quality | doctests
#   GROUP=legacy         compare with the original R/Fortran code (needs R and the
#                        compiled Fortran; see test/legacy_comparison/README.md)
#
#   julia --project=. -e 'using Pkg; Pkg.test()'
#   julia --project=. -e 'using Pkg; Pkg.test(test_args=["legacy"])'     (alternative to GROUP)

using Test
using GeocarbPrecalibration
using ForwardDiff
using HypothesisTests
using Aqua
using Documenter

const GROUP = lowercase(get(ENV, "GROUP", isempty(ARGS) ? "all" : ARGS[1]))
const G = GeocarbPrecalibration

include("testutils.jl")

rungroup(g) = GROUP == "all" ? g != "legacy" : GROUP == g

@testset "GeocarbPrecalibration" begin
    if rungroup("unit")
        @testset "model" begin
            include("model/test_numerics.jl")
            include("model/test_types.jl")
            include("model/test_climate.jl")
            include("model/test_vegetation.jl")
            include("model/test_fluxes.jl")
            include("model/test_solver.jl")
            include("model/test_run_geocarb.jl")
        end
    end
    if rungroup("io")
        @testset "io" begin
            include("io/test_csv.jl")
            include("io/test_inputs.jl")
        end
    end
    if rungroup("sampling")
        @testset "sampling" begin
            include("sampling/test_lhs.jl")
            include("sampling/test_priors.jl")
            include("sampling/test_time_series_sampler.jl")
        end
    end
    if rungroup("constraints")
        @testset "constraints" begin
            include("constraints/test_windows.jl")
            include("constraints/test_percent_outbound.jl")
        end
    end
    if rungroup("workflow")
        @testset "workflow" begin
            include("workflow/test_config.jl")
            include("workflow/test_precalibration.jl")
            include("workflow/test_analysis.jl")
        end
    end
    if rungroup("regression")
        @testset "regression" begin
            include("regression/test_fortran_golden.jl")
        end
    end
    if rungroup("quality")
        @testset "quality" begin
            include("quality/test_aqua.jl")
        end
    end
    if rungroup("doctests")
        # jldoctest blocks in docstrings; the manual pages are doctested by docs/make.jl
        DocMeta.setdocmeta!(GeocarbPrecalibration, :DocTestSetup, :(using GeocarbPrecalibration); recursive=true)
        doctest(GeocarbPrecalibration; manual=false)
    end
    if rungroup("legacy")
        include("legacy_comparison/run_comparison.jl")
    end
end
