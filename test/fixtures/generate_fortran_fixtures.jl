#!/usr/bin/env julia
#
# Generate golden-master fixtures from the compiled legacy Fortran (phase 0 of the plan).
#
#   julia --project=. test/fixtures/generate_fortran_fixtures.jl LIBDIR LABEL [N]
#
# LIBDIR contains run_geocarb.{so,dll} and run_geocarb_supp.{so,dll}; LABEL names the
# build, for example "original" (built as in the legacy README) or "real8" (built with
# `-fdefault-real-8`, which promotes the single-precision literals). N random draws
# from the priors (default 300) plus edge cases are run through both subroutines, and
# inputs and outputs are written to test/fixtures/fortran/LABEL_*.csv. The fixtures
# contain inputs *and* outputs, so the golden test needs no random numbers and no
# Fortran compiler. Existing files with the same label are overwritten.

using GeocarbPrecalibration
using GeocarbPrecalibration: write_csv, StableRNG
include(joinpath(@__DIR__, "..", "legacy_comparison", "fortran_ffi.jl"))

length(ARGS) >= 2 || error("usage: generate_fortran_fixtures.jl LIBDIR LABEL [N]")
libdir, label = ARGS[1], ARGS[2]
N = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 300
main = fortran_symbol(something(find_fortran_lib(libdir, "run_geocarb"), "missing"), :run_geocarb_)
supp = fortran_symbol(something(find_fortran_lib(libdir, "run_geocarb_supp"), "missing"), :run_geocarb_supp_)
main === nothing && error("could not load run_geocarb from $libdir")

table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
tp = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
priors = build_priors(table)
rng = StableRNG(20260101)
X = sample_constants(rng, priors, N)
sampler = InverseWishartSampler(tp)
base = parameter_vector(mean_constants(table))
cases = Tuple{String,ConstantParams{Float64},TimeForcings{Float64},Int}[]
push!(cases, ("means", mean_constants(table), tp.center, 10))
for i in 1:N
    v = copy(base)
    for (j, p) in enumerate(priors)
        v[findfirst(==(p.name), CONSTANT_PARAMETER_NAMES)] = X[i, j]
    end
    f = copy(tp.center)
    sample_time_forcings!(rng, f, sampler)
    push!(cases, ("draw$i", GeocarbPrecalibration._constants_from_vector(Float64, v), f, 10))
end
pm = mean_constants(table)
push!(cases, ("not_converged", pm, tp.center, 1))
push!(cases, ("huge_sensitivity", update(pm; deltaT2X = 50.0), tp.center, 10))
fneg = copy(tp.center); fneg.GEOG .= -1e4
push!(cases, ("negative_power_base", pm, fneg, 10))

supp_cfgs = [("control", 130, 80, 1, -1), ("gym", 130, 80, 0.25, -1), ("timing", 110, 60, 1, -1),
             ("gym_timing", 110, 60, 0.25, -1), ("dT2X", 130, 80, 1, 1), ("gym_timing_dT2X", 110, 60, 0.25, 1)]

outdir = mkpath(joinpath(@__DIR__, "fortran"))
nt = length(tp.center.age)
cnames = String.(collect(CONSTANT_PARAMETER_NAMES))
fnames = ["$(n)_$k" for n in TIME_FORCING_NAMES for k in 1:nt]
write_csv(joinpath(outdir, "$(label)_inputs.csv"), vcat(["case", "iteration_threshold"], cnames, fnames),
          vcat([[c[1] for c in cases], [c[4] for c in cases]],
               [[getfield(c[2], n) for c in cases] for n in CONSTANT_PARAMETER_NAMES],
               [[getfield(c[3], n)[k] for c in cases] for n in TIME_FORCING_NAMES for k in 1:nt]))
# temperatures are stored as temp + 15, the quantity the R code exports
function dump_runs(name, runs)
    for (q, out, shift) in (("co2", 1, 0.0), ("o2", 2, 0.0), ("temp15", 3, 15.0))
        write_csv(joinpath(outdir, "$(label)_$(name)_$(q).csv"), ["step_$k" for k in 1:nt],
                  [[r[out][k] + shift for r in runs] for k in 1:nt])
    end
end
dump_runs("main", [fortran_run(main, c[2], c[3]; iteration_threshold = c[4]) for c in cases])
if supp !== nothing
    for (nm, b, e, g, d) in supp_cfgs
        dump_runs("supp_$nm", [fortran_run_supp(supp, c[2], c[3], b, e, g, d; iteration_threshold = c[4]) for c in cases])
    end
end
println("wrote fixtures for $(length(cases)) cases to $outdir")
