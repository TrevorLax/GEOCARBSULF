# prepare_ensemble.jl: build the shared ensemble analysed by both implementations
# (plan §5.3). The legacy .RData of the paper experiments are not in the repository, so a
# posterior-like ensemble is generated here: run_precalibration with the CO2 + temperature
# constraint at `threshold`, until `n` samples are accepted (multivariate-t sampler and all
# threads, only to make this preparation fast; it is not a timed component).
#
#   julia --project=benchmark/timing -t auto prepare_ensemble.jl <out_dir> <n> <threshold> <seed>
#
# Writes result.jld2 plus raw little-endian Float64 files and names for r/prepare_ensemble.R.

using GeocarbPrecalibration
out, n, thr, seed = ARGS[1], parse(Int, ARGS[2]), parse(Float64, ARGS[3]), parse(Int, ARGS[4])
mkpath(out)
cfg = ExperimentConfig(; name = "ensemble", tag = "ensemble", constraint = :both, threshold = thr,
                       n_sample = 200_000_000, n_per_chunk = 10_000, n_accept_min = n, seed = seed,
                       time_sampler = :multivariate_t, constant_design = :chunked_lhs)
t = @elapsed r = run_precalibration(cfg; verbose = true)
n_accepted(r) == n || error("ensemble: only $(n_accepted(r)) samples accepted")
save_result(joinpath(out, "result.jld2"), r)
write(joinpath(out, "constants.f64"), r.constants)                          # n × 56, column major
write(joinpath(out, "time_series.f64"), r.time_series)                      # 58 × n × 12
write(joinpath(out, "co2.f64"), r.co2); write(joinpath(out, "temp.f64"), r.temp); write(joinpath(out, "o2.f64"), r.o2)
write(joinpath(out, "prcout.f64"), hcat(r.prcout_co2, r.prcout_temp))
open(io -> println(io, join(String.(r.constant_names), ",")), joinpath(out, "constant_names.txt"), "w")
open(io -> println(io, join(String.(r.forcing_names), ",")), joinpath(out, "forcing_names.txt"), "w")
open(joinpath(out, "ensemble.toml"), "w") do io
    println(io, "n = $n\nthreshold = $thr\nseed = $seed\nn_simulated = $(r.n_simulated)\nseconds = $t")
end
println("ensemble: $n accepted of $(r.n_simulated) simulated in $(round(t; digits = 1)) s")
