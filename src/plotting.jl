# Plotting functions. They are implemented in the package extension
# `ext/GeocarbMakieExt.jl`, which loads automatically when a Makie backend is loaded:
#
#     using GeocarbPrecalibration, CairoMakie
#
# Without a backend these functions have no methods, and calling them gives a
# MethodError that points here.

"""
    plot_model_vs_proxy(res, proxy::ProxyData, temp_windows::Windows; probs_bands = ...) -> Figure

Hindcast CO2 and temperature bands against CO2 proxies and temperature windows (R
figure `model_vs_proxy.pdf`). Requires a Makie backend (`using CairoMakie`).
"""
function plot_model_vs_proxy end

"""
    plot_deltaT2X_distributions(res; prior = nothing, park_royer = nothing) -> Figure

Posterior density of ΔT2x (and ΔT2x·GLAC), with the prior and the Park & Royer (2011)
distribution (R figure `deltaT2X_distributions.pdf`). Requires a Makie backend.
"""
function plot_deltaT2X_distributions end

"""
    plot_deltaT2X_experiments(results::AbstractDict{String,PrecalibrationResult}) -> Figure

ΔT2x quantile ranges across experiments (R figure `deltaT2X_experiments.pdf`).
Requires a Makie backend.
"""
function plot_deltaT2X_experiments end

"""
    plot_time_series_parameters(res, prior_quantiles) -> Figure

Prior and precalibrated 95 % bands of the 12 forcings (R figure
`time_series_parameters.pdf`). Requires a Makie backend.
"""
function plot_time_series_parameters end

"""
    plot_co2_windows_and_proxies(proxy::ProxyData, co2::Windows) -> Figure

CO2 windows and proxy data points (R figure `co2_windows_and_proxies.pdf`). Requires a
Makie backend.
"""
function plot_co2_windows_and_proxies end

"""
    plot_gym_modification(; GYM = 0.875, LIFE = 0.25, options = ModelOptions(gym_angio_transition = (110, 60), gym_factor = 0.25)) -> Figure

fE through time for the default and a modified vegetation history (R figure
`gym_modification.pdf`). Requires a Makie backend.
"""
function plot_gym_modification end

"""
    plot_time_series_autocorrelations(res; lag_max = 10) -> Figure

Autocorrelation quantiles of the accepted forcing series (R figure
`time_series_autocorrelations.pdf`). Requires a Makie backend.
"""
function plot_time_series_autocorrelations end
