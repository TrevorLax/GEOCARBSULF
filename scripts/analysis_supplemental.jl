#!/usr/bin/env julia
#
# Analysis of the supplemental experiments (replaces analysis_supplemental_experiments.R).
#
#   julia --project=. -t auto scripts/run_experiment.jl experiments/supplemental/gym.toml   (etc.)
#   julia --project=. scripts/analysis_supplemental.jl [results]
#
# Compares each supplemental experiment with the control (main ct_out50 experiment):
# the share of its accepted samples whose temperature % outbound is below 40, 30 and
# 25 %, and ΔT2x quantiles. Writes results/supplemental/numbers.toml.

using GeocarbPrecalibration
using TOML

root = isempty(ARGS) ? "results" : ARGS[1]
experiments = [
    "control" => joinpath(root, "main", "ct_out50", "result.jld2"),
    "gym" => joinpath(root, "supplemental", "ct_out50_gym", "result.jld2"),
    "timing" => joinpath(root, "supplemental", "ct_out50_timing", "result.jld2"),
    "gym+timing" => joinpath(root, "supplemental", "ct_out50_gym+timing", "result.jld2"),
    "dT2X" => joinpath(root, "supplemental", "ct_out50_dT2X", "result.jld2"),
    "gym+timing+dT2X" => joinpath(root, "supplemental", "ct_out50_gym+timing+dT2X", "result.jld2"),
]

numbers = Dict{String,Any}()
for (name, file) in experiments
    isfile(file) || (println("missing $file, skipped"); continue)
    r = load_result(file)
    n = n_accepted(r)
    n == 0 && continue
    s = climate_sensitivity_summary(r)
    numbers[name] = Dict(
        "n_accepted" => n,
        "deltaT2X_5_50_95" => s.deltaT2X,
        "frac_temp_prcout_below_40pct" => count(<(0.4), r.prcout_temp) / n,
        "frac_temp_prcout_below_30pct" => count(<(0.3), r.prcout_temp) / n,
        "frac_temp_prcout_below_25pct" => count(<(0.25), r.prcout_temp) / n,
    )
end
out = mkpath(joinpath(root, "supplemental"))
open(joinpath(out, "numbers.toml"), "w") do io
    TOML.print(io, numbers; sorted = true)
end
println("wrote ", joinpath(out, "numbers.toml"))
