#!/usr/bin/env julia
#
# Analysis of the Cretaceous temperature-matching experiment (replaces
# cretaceous_experiment.R).
#
#   julia --project=. -t auto scripts/run_experiment.jl experiments/main/grid.toml
#   julia --project=. -t auto scripts/run_experiment.jl experiments/main/ct_out30_extra_seeds.toml
#   julia --project=. -t auto scripts/run_experiment.jl experiments/cretaceous/stage1.toml
#   julia --project=. -t auto scripts/run_experiment.jl experiments/cretaceous/stage2.toml
#   julia --project=. scripts/analysis_cretaceous.jl [results]
#
# Writes results/cretaceous/numbers.toml with ΔT2x and ΔT2x·GLAC summaries of the
# Cretaceous-matching ensembles and of their controls, and the strongest Spearman
# correlations between the Cretaceous-age temperature and the constant parameters:
#
#   control_ct_out30   main ct_out30, all three seeds merged (control for stage 2, 30 %)
#   control_ct_out50   main ct_out50 (control for stage 1, 50 %)
#   cretaceous_stage1  ct_out50_cret
#   cretaceous_stage2  ct_out30_cret
#
# Temperatures are `temp + T0` with the T0 of each result's configuration, and the
# Cretaceous age is the `cretaceous_age` of the stage-1 configuration.

using GeocarbPrecalibration
using TOML

root = isempty(ARGS) ? "results" : ARGS[1]

load(path) = isfile(path) ? load_result(path) : (println("missing $path, skipped"); nothing)

function load_merged(tag, paths)
    parts = PrecalibrationResult[r for r in map(load, paths) if r !== nothing]
    isempty(parts) && return nothing
    length(parts) < length(paths) &&
        @warn "$tag: only $(length(parts)) of $(length(paths)) seeds found; the control ensemble is incomplete"
    return length(parts) == 1 ? only(parts) : merge_results(parts; tag=tag)
end

main = joinpath(root, "main")
ensembles = [
    "control_ct_out30" => load_merged(
        "ct_out30",
        [joinpath(main, t, "result.jld2") for t in ("ct_out30", "ct_out30_seed11", "ct_out30_seed2020")],
    ),
    "control_ct_out50" => load(joinpath(main, "ct_out50", "result.jld2")),
    "cretaceous_stage1" => load(joinpath(root, "cretaceous", "ct_out50_cret", "result.jld2")),
    "cretaceous_stage2" => load(joinpath(root, "cretaceous", "ct_out30_cret", "result.jld2")),
]

# The age at which the Cretaceous experiments matched temperatures, from their own
# configuration (the controls have none).
age_cret = let
    cret = [r for (name, r) in ensembles if startswith(name, "cretaceous") && r !== nothing]
    ages = unique(Float64(r.config["cretaceous_age"]) for r in cret if haskey(r.config, "cretaceous_age"))
    length(ages) > 1 && error("the Cretaceous results use different cretaceous_age values: $ages")
    isempty(ages) ? 90.0 : only(ages)
end

numbers = Dict{String,Any}("cretaceous_age" => age_cret)
for (name, r) in ensembles
    (r === nothing || n_accepted(r) == 0) && continue
    s = climate_sensitivity_summary(r)
    i = findfirst(==(age_cret), r.age)
    i === nothing && error("$name: age $age_cret Ma is not on the result's age grid")
    t_cret = accepted_temperature(r)[i, :]
    screen = correlation_screen(r, t_cret)
    numbers[name] = Dict(
        "n_accepted" => n_accepted(r),
        "deltaT2X_5_50_95" => s.deltaT2X,
        "deltaT2X_glacial_5_50_95" => s.deltaT2X_glacial,
        "top_spearman_with_T_cretaceous" =>
            Dict(String(screen.names[k]) => screen.r[k] for k in 1:min(5, length(screen.names))),
    )
end
out = mkpath(joinpath(root, "cretaceous"))
open(joinpath(out, "numbers.toml"), "w") do io
    return TOML.print(io, numbers; sorted=true)
end
println("wrote ", joinpath(out, "numbers.toml"))
