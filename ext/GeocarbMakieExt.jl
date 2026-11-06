"""
Figures of the GEOCARB precalibration analysis, drawn with Makie. Loaded automatically
by `using GeocarbPrecalibration, CairoMakie` (or any other Makie backend). Save a
figure with `save("figure.pdf", fig)`.
"""
module GeocarbMakieExt

using GeocarbPrecalibration
using GeocarbPrecalibration: PrecalibrationResult, ProxyData, Windows, ModelOptions,
    TruncatedPrior, DEFAULT_PROBS, TIME_FORCING_NAMES, hindcast, row_quantiles, gaussian_kde,
    time_series_quantiles, acf_quantiles, constant_column, prior_pdf, vegetation_fE,
    mean_constants, read_prior_table, datapath, update, parameter_units
import GeocarbPrecalibration: plot_model_vs_proxy, plot_deltaT2X_distributions, plot_deltaT2X_experiments,
    plot_time_series_parameters, plot_co2_windows_and_proxies, plot_gym_modification,
    plot_time_series_autocorrelations
using Makie

const BAND_PROBS = [0.025, 0.05, 0.25, 0.5, 0.75, 0.95, 0.975]

function _bands!(ax, x, q, color; positive = false)
    for (lo, hi, a) in ((1, 7, 0.25), (2, 6, 0.45), (3, 5, 0.65))
        ok = isfinite.(q[:, lo]) .& isfinite.(q[:, hi])
        positive && (ok .&= (q[:, lo] .> 0))
        any(ok) && band!(ax, x[ok], q[ok, lo], q[ok, hi]; color = (color, a))
    end
    ok = isfinite.(q[:, 4])
    positive && (ok .&= (q[:, 4] .> 0))
    any(ok) && lines!(ax, x[ok], q[ok, 4]; color = color, linewidth = 1.5)
    return ax
end

function plot_model_vs_proxy(res::PrecalibrationResult, proxy::ProxyData, temp_windows::Windows;
                             xlims = (-425, 0))
    hc = hindcast(res)
    qc = row_quantiles(hc.co2; probs = BAND_PROBS)
    qt = row_quantiles(hc.temp; probs = BAND_PROBS)
    x = -res.age
    fig = Figure(; size = (500, 750))
    ax1 = Axis(fig[1, 1]; ylabel = "CO₂ concentration [ppmv]", yscale = log10,
               title = "Hindcast vs proxies ($(res.tag))")
    scatter!(ax1, -proxy.age, proxy.co2; markersize = 3, color = (:black, 0.4))
    _bands!(ax1, x, qc, :royalblue; positive = true)
    xlims!(ax1, xlims...)
    ax2 = Axis(fig[2, 1]; xlabel = "Time [Myr ago]", ylabel = "Global mean temperature [°C]")
    band!(ax2, x, temp_windows.low, temp_windows.high; color = (:gray, 0.3))
    _bands!(ax2, x, qt, :firebrick)
    xlims!(ax2, xlims...)
    return fig
end

function plot_deltaT2X_distributions(res::PrecalibrationResult; prior::Union{Nothing,TruncatedPrior} = nothing,
                                     park_royer = nothing)
    s = constant_column(res, :deltaT2X)
    g = s .* constant_column(res, :GLAC)
    k1 = gaussian_kde(s; from = 0, to = 10)
    k2 = gaussian_kde(g; from = 0, to = 25)
    fig = Figure(; size = (600, 400))
    ax = Axis(fig[1, 1]; xlabel = "ΔT₂ₓ [°C]", ylabel = "Density")
    lines!(ax, k1.x, k1.density; color = :steelblue, linewidth = 2, label = "Posterior, this study")
    lines!(ax, k2.x, k2.density; color = :salmon, linewidth = 2, linestyle = :dashdot, label = "Posterior (glacial)")
    if prior !== nothing
        xs = range(0.01, 10; length = 400)
        lines!(ax, xs, [prior_pdf(prior, v) for v in xs]; color = :black, linestyle = :dot, label = "Prior")
    end
    if park_royer !== nothing
        lines!(ax, park_royer.deltaT2X, park_royer.pdf ./ maximum(park_royer.pdf) .* maximum(k1.density);
               color = :black, linestyle = :dash, label = "Park & Royer (2011), rescaled")
    end
    xlims!(ax, 0, 15)
    axislegend(ax; position = :rt)
    return fig
end

function plot_deltaT2X_experiments(results::AbstractDict{<:AbstractString,PrecalibrationResult})
    names = sort!(collect(keys(results)))
    fig = Figure(; size = (450, 120 + 30 * length(names)))
    ax = Axis(fig[1, 1]; xlabel = "ΔT₂ₓ [°C]", yticks = (1:length(names), names))
    for (i, nm) in enumerate(names)
        q = GeocarbPrecalibration.Statistics.quantile(constant_column(results[nm], :deltaT2X), [0.05, 0.25, 0.5, 0.75, 0.95])
        lines!(ax, [q[1], q[5]], [i, i]; color = :gray, linewidth = 1.5)
        lines!(ax, [q[2], q[4]], [i, i]; color = :black, linewidth = 4)
        scatter!(ax, [q[3]], [i]; color = :white, strokecolor = :black, strokewidth = 1.5, markersize = 9)
    end
    return fig
end

function plot_time_series_parameters(res::PrecalibrationResult, prior_quantiles::AbstractArray{<:Real,3})
    post = time_series_quantiles(res; probs = DEFAULT_PROBS)
    lo = findfirst(==(0.025), DEFAULT_PROBS); hi = findfirst(==(0.975), DEFAULT_PROBS)
    md = findfirst(==(0.5), DEFAULT_PROBS)
    x = -res.age
    fig = Figure(; size = (800, 1000))
    for (j, nm) in enumerate(TIME_FORCING_NAMES)
        r, c = divrem(j - 1, 3)
        ax = Axis(fig[r+1, c+1]; title = String(nm), ylabel = parameter_units(nm),
                  xlabel = r == 3 ? "Time [Myr ago]" : "")
        band!(ax, x, prior_quantiles[:, lo, j], prior_quantiles[:, hi, j]; color = (:gray, 0.4))
        lines!(ax, x, prior_quantiles[:, md, j]; color = :gray40)
        band!(ax, x, post[:, lo, j], post[:, hi, j]; color = (:darkred, 0.25))
        lines!(ax, x, post[:, md, j]; color = :darkred)
        xlims!(ax, -450, 0)
    end
    return fig
end

function plot_co2_windows_and_proxies(proxy::ProxyData, w::Windows)
    fig = Figure(; size = (600, 450))
    ax = Axis(fig[1, 1]; xlabel = "Time [Myr ago]", ylabel = "CO₂ [ppmv]", yscale = log10)
    ok = w.low .> 0
    band!(ax, -w.age[ok], w.low[ok], w.high[ok]; color = (:royalblue, 0.25), label = "windows")
    scatter!(ax, -proxy.age, proxy.co2; markersize = 4, color = :black, label = "proxies")
    xlims!(ax, -425, 0)
    axislegend(ax; position = :rt)
    return fig
end

function plot_gym_modification(; GYM::Real = 0.875, LIFE::Real = 0.25,
                               options::ModelOptions = ModelOptions(gym_angio_transition = (110, 60), gym_factor = 0.25))
    p = update(mean_constants(read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))); GYM = GYM, LIFE = LIFE)
    t = collect(570.0:-1.0:0.0)
    f0 = [vegetation_fE(ti, p, ModelOptions()) for ti in t]
    f1 = [vegetation_fE(ti, p, options) for ti in t]
    fig = Figure(; size = (550, 400))
    ax = Axis(fig[1, 1]; xlabel = "Age [Myr ago]", ylabel = "fE [unitless]")
    lines!(ax, -t, f0; color = :black, label = "Original default values")
    lines!(ax, -t, f1; color = :firebrick, linestyle = :dash, label = "Modified")
    axislegend(ax; position = :lt)
    return fig
end

function plot_time_series_autocorrelations(res::PrecalibrationResult; lag_max::Integer = 10)
    q = acf_quantiles(res; lag_max = lag_max, probs = DEFAULT_PROBS)
    lo = findfirst(==(0.025), DEFAULT_PROBS); hi = findfirst(==(0.975), DEFAULT_PROBS)
    md = findfirst(==(0.5), DEFAULT_PROBS)
    lags = collect(0:lag_max)
    fig = Figure(; size = (800, 1000))
    for (j, nm) in enumerate(TIME_FORCING_NAMES)
        r, c = divrem(j - 1, 3)
        ax = Axis(fig[r+1, c+1]; title = String(nm), xlabel = r == 3 ? "Lag [time steps]" : "")
        band!(ax, lags, q[:, lo, j], q[:, hi, j]; color = (:gray, 0.5))
        lines!(ax, lags, q[:, md, j]; color = :black, linewidth = 1.5)
        ylims!(ax, -0.1, 1)
    end
    return fig
end

end # module
