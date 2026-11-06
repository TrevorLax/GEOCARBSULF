# Static type-stability analysis of the model hot path with JET.jl (not part of
# Pkg.test because JET versions are tied to Julia versions):
#   julia --project=. -e 'using Pkg; Pkg.add("JET")'   (or install it globally)
#   julia --project=. test/jet.jl
using JET
using GeocarbPrecalibration
table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
f = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv")).center
p = mean_constants(table)
out = GeocarbResult{Float64}(f.age)
@report_opt run_geocarb!(out, p, f)
