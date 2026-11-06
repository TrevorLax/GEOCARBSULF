#!/usr/bin/env julia
#
# Analysis of the main-text experiments (replaces the numerical part of
# analysis_and_plots.R). Run the experiments first:
#
#   julia --project=. -t auto scripts/run_experiment.jl experiments/main/grid.toml
#   julia --project=. -t auto scripts/run_experiment.jl experiments/main/ct_out30_extra_seeds.toml
#   julia --project=. scripts/analysis_main.jl [results/main]
#
# Writes <dir>/numbers.toml (the numbers quoted in the manuscript) and
# <dir>/som_parameters_table.csv. If CairoMakie is installed (in this project or in
# your default environment), figures are written to <dir>/figures/.

using GeocarbPrecalibration
using GeocarbPrecalibration: write_csv
using TOML

dir = isempty(ARGS) ? joinpath("results", "main") : ARGS[1]
isdir(dir) || error("result directory $dir not found; run the experiments first")

function load_tag(tag)
    f = joinpath(dir, tag, "result.jld2")
    return isfile(f) ? load_result(f) : nothing
end

results = Dict{String,PrecalibrationResult}()
for c in ("c", "t", "ct"), th in (30, 35, 40, 45, 50)
    tag = "$(c)_out$(th)"
    r = load_tag(tag)
    r === nothing && (println("missing $tag, skipped"); continue)
    if tag == "ct_out30"
        extra = PrecalibrationResult[x for x in (load_tag("ct_out30_seed11"), load_tag("ct_out30_seed2020")) if x !== nothing]
        isempty(extra) || (r = merge_results(vcat(PrecalibrationResult[r], extra); tag = "ct_out30"))
    end
    results[tag] = r
end
isempty(results) && error("no results found in $dir")

numbers = Dict{String,Any}()
for (tag, r) in results
    n_accepted(r) == 0 && continue
    s = climate_sensitivity_summary(r)
    numbers[tag] = Dict(
        "n_accepted" => n_accepted(r), "n_simulated" => r.n_simulated,
        "deltaT2X_5_50_95" => s.deltaT2X, "GLAC_5_50_95" => s.GLAC,
        "deltaT2X_glacial_5_50_95" => s.deltaT2X_glacial,
        "Pr_deltaT2X_ge_6" => s.prob_exceed[6.0], "Pr_deltaT2X_ge_7" => s.prob_exceed[7.0],
        "frac_prcout_co2_below_25pct" => count(<(0.25), r.prcout_co2) / n_accepted(r),
        "frac_prcout_temp_below_25pct" => count(<(0.25), r.prcout_temp) / n_accepted(r),
    )
end
open(joinpath(dir, "numbers.toml"), "w") do io
    TOML.print(io, numbers; sorted = true)
end
println("wrote ", joinpath(dir, "numbers.toml"))

if haskey(results, "ct_out30") && n_accepted(results["ct_out30"]) > 0
    table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
    t = prior_posterior_table(table, results["ct_out30"])
    write_csv(joinpath(dir, "som_parameters_table.csv"), collect(String.(keys(t))), collect(values(t)))
    println("wrote ", joinpath(dir, "som_parameters_table.csv"))
end

plotting = try
    @eval using CairoMakie
    true
catch
    println("CairoMakie not available: figures skipped (install it with `] add CairoMakie`)")
    false
end
if plotting && haskey(results, "ct_out30")
    figdir = mkpath(joinpath(dir, "figures"))
    r = results["ct_out30"]
    proxy = read_proxy_data(datapath("CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv"))
    tw = temperature_windows(read_temperature_data(datapath("Mills_GR_2019_temp_co2.csv")), r.age)
    cw = co2_windows(proxy, r.age)
    table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
    prior = TruncatedPrior(GeocarbPrecalibration.spec(table, :deltaT2X))
    pr = read_park_royer_2011(datapath("ParkRoyer2011_Fig3_85varred.csv"))
    figs = Dict(
        "model_vs_proxy.pdf" => () -> plot_model_vs_proxy(r, proxy, tw),
        "deltaT2X_distributions.pdf" => () -> plot_deltaT2X_distributions(r; prior = prior, park_royer = pr),
        "deltaT2X_experiments.pdf" => () -> plot_deltaT2X_experiments(results),
        "co2_windows_and_proxies.pdf" => () -> plot_co2_windows_and_proxies(proxy, cw),
        "gym_modification.pdf" => () -> plot_gym_modification(),
        "time_series_autocorrelations.pdf" => () -> plot_time_series_autocorrelations(r),
    )
    for (name, f) in figs
        fig = Base.invokelatest(f)
        Base.invokelatest(CairoMakie.save, joinpath(figdir, name), fig)
        println("wrote ", joinpath(figdir, name))
    end
end
