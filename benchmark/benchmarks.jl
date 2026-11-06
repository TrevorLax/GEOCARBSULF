# Benchmarks (needs BenchmarkTools in your environment):
#   julia --project=. -e 'using Pkg; Pkg.add("BenchmarkTools")'   (or install it globally)
#   julia --project=. benchmark/benchmarks.jl
using BenchmarkTools
using GeocarbPrecalibration
using GeocarbPrecalibration: StableRNG

table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
tp = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
p = mean_constants(table)
f = copy(tp.center)
out = GeocarbResult{Float64}(f.age)
iw = InverseWishartSampler(tp)
mt = MultivariateTSampler(tp)
rng = StableRNG(1)

const SUITE = BenchmarkGroup()
SUITE["model"]["run_geocarb!"] = @benchmarkable run_geocarb!($out, $p, $f)
SUITE["sampler"]["inverse_wishart"] = @benchmarkable sample_time_forcings!($rng, $f, $iw)
SUITE["sampler"]["multivariate_t"] = @benchmarkable sample_time_forcings!($rng, $f, $mt)
SUITE["sampler"]["lhs_10000x56"] = @benchmarkable random_lhs($rng, 10_000, 56)

if abspath(PROGRAM_FILE) == @__FILE__
    results = run(SUITE; verbose = true)
    show(stdout, MIME"text/plain"(), results)
    println()
end
