"""
    Windows

Lower and upper bounds of a precalibration window at every model time step. The
constructor requires `low ≤ high` at every step.
"""
struct Windows
    age::Vector{Float64}
    low::Vector{Float64}
    high::Vector{Float64}
    function Windows(age, low, high)
        length(age) == length(low) == length(high) ||
            throw(ArgumentError("age, low and high must have the same length"))
        # an inverted window would reject every run (J-24)
        for i in eachindex(low, high)
            low[i] <= high[i] ||
                throw(ArgumentError("window at age $(age[i]) has low = $(low[i]) > high = $(high[i]) (or NaN)"))
        end
        return new(collect(Float64, age), collect(Float64, low), collect(Float64, high))
    end
end

Base.length(w::Windows) = length(w.age)

"""
    shift(w::Windows, delta::AbstractVector) -> Windows

Window moved by `delta` at every step, for analysis and plotting (the precalibration
itself does not shift windows). For example, `shift(w, Ws .* w.age ./ 570)`
removes the solar-luminosity term from temperature windows, for comparison with a
CO2-only temperature (the R code did this with the fixed prior mean of `Ws`, finding
F-19).
"""
shift(w::Windows, delta::AbstractVector) = Windows(w.age, w.low .+ delta, w.high .+ delta)

"""
    co2_windows(proxy::ProxyData, age; nsig = 1.0, bounds = (0.0, 50_000.0), dt = grid spacing) -> Windows

CO2 windows, as in the R code. For each model step, the proxies within ±dt/2 of
its age are pooled (the bins of [`proxy_step_index`](@ref)). Each proxy spans
`log10(co2) ± nsig·log10(co2_high/co2)`, and the window is the envelope of those spans,
intersected with `bounds`. Steps without data get the full `bounds`. `dt` defaults to
the spacing of `age`; a single-step grid needs it explicitly.

`bounds` must overlap the envelope at every step: `bounds[2]` must be at least the
lowest proxy span bound (`10^min(log10(co2) − nsig·σ)`) of each step, and `bounds[1]` at
most its highest. Otherwise the intersection is empty and the [`Windows`](@ref)
constructor throws an `ArgumentError` naming the step.
"""
function co2_windows(
    proxy::ProxyData, age::AbstractVector; nsig::Real=1.0, bounds=(0.0, 50_000.0), dt::Real=_grid_spacing(age)
)
    n = length(age)
    bins = _step_bins(proxy.age, age, dt)
    low = fill(Float64(bounds[1]), n)
    high = fill(Float64(bounds[2]), n)
    for tt in 1:n
        idx = findall(==(tt), bins)
        isempty(idx) && continue
        sigmas = log10.(proxy.co2_high[idx] ./ proxy.co2[idx])
        centers = log10.(proxy.co2[idx])
        tops = centers .+ nsig .* sigmas
        bots = centers .- nsig .* sigmas
        tops_max = 10.0^maximum(tops)
        bots_min = 10.0^minimum(bots)
        low[tt] = max(bots_min, low[tt])
        high[tt] = min(tops_max, high[tt])
    end
    return Windows(age, low, high)
end

"""
    temperature_windows(data::TemperatureData, age; nsig = 1.0) -> Windows

Temperature windows from Mills et al. (2019), as in the R code:
`[T_avg − nsig·(T_avg − T_min), T_avg + nsig·(T_max − T_avg)]` at the record whose
`time` equals `−age`. The windows are actual temperatures, so they include the
solar-luminosity effect. They are compared with `temp + T0` from the model, which
includes the solar term `−Ws·t/570` as well (see [`surface_temperature`](@ref)).
"""
function temperature_windows(data::TemperatureData, age::AbstractVector; nsig::Real=1.0)
    upper = data.T_avg .+ nsig .* (data.T_max .- data.T_avg)
    lower = data.T_avg .- nsig .* (data.T_avg .- data.T_min)
    low = similar(collect(Float64, age))
    high = similar(low)
    for (tt, a) in enumerate(age)
        j = findfirst(==(-a), data.time)
        j === nothing && throw(ArgumentError("no temperature record at time $(-a) Ma"))
        low[tt] = lower[j]
        high[tt] = upper[j]
        (isfinite(low[tt]) && isfinite(high[tt])) ||
            throw(ArgumentError("temperature record at $(-a) Ma has missing values"))
    end
    return Windows(age, low, high)
end
