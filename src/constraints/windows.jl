"""
    Windows

Lower and upper bounds of a precalibration window at every model time step.
"""
struct Windows
    age::Vector{Float64}
    low::Vector{Float64}
    high::Vector{Float64}
    function Windows(age, low, high)
        length(age) == length(low) == length(high) ||
            throw(ArgumentError("age, low and high must have the same length"))
        return new(collect(Float64, age), collect(Float64, low), collect(Float64, high))
    end
end

Base.length(w::Windows) = length(w.age)

"""
    shift(w::Windows, delta::AbstractVector) -> Windows

Window moved by `delta` at every step (for example to add the solar term back in for
plotting; `constraints.R:72-73` did this with the fixed prior mean of `Ws`, finding F-19).
"""
shift(w::Windows, delta::AbstractVector) = Windows(w.age, w.low .+ delta, w.high .+ delta)

"""
    co2_windows(proxy::ProxyData, age; nsig = 1.0, bounds = (0.0, 50_000.0)) -> Windows

CO2 windows (`constraints.R:28-43`). For each model step, the proxies within ±dt/2 of
its age are pooled. Each proxy spans `log10(co2) ± nsig·log10(co2_high/co2)`, and the
window is the envelope of those spans, intersected with `bounds`. Steps without data
get the full `bounds`.
"""
function co2_windows(proxy::ProxyData, age::AbstractVector; nsig::Real=1.0, bounds=(0.0, 50_000.0))
    n = length(age)
    dt = n > 1 ? abs(age[1] - age[2]) : 10.0
    half = 0.5 * dt
    low = fill(Float64(bounds[1]), n)
    high = fill(Float64(bounds[2]), n)
    for tt in 1:n
        idx = findall(a -> (a < age[tt] + half) && (a >= age[tt] - half), proxy.age)
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

Temperature windows from Mills et al. (2019) (`constraints.R:51-71`):
`[T_avg − nsig·(T_avg − T_min), T_avg + nsig·(T_max − T_avg)]` at the record whose
`time` equals `−age`. The windows include the solar-luminosity effect and are compared
with `temp + 15` from the model (see [`temperature`](@ref)).
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
