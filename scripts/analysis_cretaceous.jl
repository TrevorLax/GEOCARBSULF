#!/usr/bin/env julia
#
# Analysis of the Cretaceous temperature-matching experiment (replaces
# cretaceous_experiment.R).
#
#   julia --project=. -t auto scripts/run_experiment.jl experiments/cretaceous/stage1.toml
#   julia --project=. -t auto scripts/run_experiment.jl experiments/cretaceous/stage2.toml
#   julia --project=. scripts/analysis_cretaceous.jl [results]
#
# Writes results/cretaceous/numbers.toml with ΔT2x and ΔT2x·GLAC summaries of the control
# (main ct_out30) and Cretaceous-matching ensembles, and the strongest Spearman
# correlations between the 90 Ma temperature and the constant parameters.

using GeocarbPrecalibration
using TOML

root = isempty(ARGS) ? "results" : ARGS[1]
files = [
    "control" => joinpath(root, "main", "ct_out30", "result.jld2"),
    "cretaceous_stage1" => joinpath(root, "cretaceous", "ct_out50_cret", "result.jld2"),
    "cretaceous_stage2" => joinpath(root, "cretaceous", "ct_out30_cret", "result.jld2"),
]
age_cret = 90.0

numbers = Dict{String,Any}()
for (name, file) in files
    isfile(file) || (println("missing $file, skipped"); continue)
    r = load_result(file)
    n_accepted(r) == 0 && continue
    s = climate_sensitivity_summary(r)
    i = findfirst(==(age_cret), r.age)
    t90 = r.temp[i, :] .+ 15
    screen = correlation_screen(r, t90)
    numbers[name] = Dict(
        "n_accepted" => n_accepted(r),
        "deltaT2X_5_50_95" => s.deltaT2X,
        "deltaT2X_glacial_5_50_95" => s.deltaT2X_glacial,
        "top_spearman_with_T90" => Dict(String(screen.names[k]) => screen.r[k] for k in 1:5),
    )
end
out = mkpath(joinpath(root, "cretaceous"))
open(joinpath(out, "numbers.toml"), "w") do io
    TOML.print(io, numbers; sorted=true)
end
println("wrote ", joinpath(out, "numbers.toml"))
