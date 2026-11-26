"Proxy types assimilated by default (those of the R code)."
const DEFAULT_PROXIES = (:paleosols, :alkenones, :stomata, :boron, :liverworts)

"""
    ProxyData

CO2 proxy observations (Foster et al. 2017 compilation). Ages in Myr ago, CO2 in
ppmv. `co2_low` and `co2_high` are the ±1σ bounds given in the file.
"""
struct ProxyData
    age::Vector{Float64}
    co2::Vector{Float64}
    co2_low::Vector{Float64}
    co2_high::Vector{Float64}
    proxy_type::Vector{Symbol}
    reference::Vector{String}
end

Base.length(d::ProxyData) = length(d.age)

"""
    read_proxy_data(path; proxies = $(DEFAULT_PROXIES)) -> ProxyData

Read a CO2 proxy CSV (columns `age, co2, co2_low, co2_high, proxy_type, reference`;
other columns are ignored) and keep the listed proxy types. As in the R code, rows are
grouped by proxy type in the order of `proxies`. Each kept row must satisfy
`co2_low ≤ co2 ≤ co2_high` (`co2_low` may be missing).
"""
function read_proxy_data(path::AbstractString; proxies=DEFAULT_PROXIES)
    t = read_csv_table(path)
    age = numeric_column(t, "age")
    co2 = numeric_column(t, "co2")
    lo = numeric_column(t, "co2_low"; allow_missing=true)
    hi = numeric_column(t, "co2_high")
    ptype = Symbol.(column(t, "proxy_type"))
    ref = has_column(t, "reference") ? column(t, "reference") : fill("", length(age))
    known = Set(ptype)
    for p in proxies
        Symbol(p) in known || @warn "proxy type :$p does not occur in $path"
    end
    idx = Int[]
    for p in proxies
        append!(idx, findall(==(Symbol(p)), ptype))
    end
    for i in idx
        (co2[i] > 0 && hi[i] > 0) || throw(ArgumentError("$path:$(t.lines[i]): co2 and co2_high must be positive"))
        # an inverted row gives an inverted window that rejects every run (J-24)
        co2[i] <= hi[i] || throw(ArgumentError("$path:$(t.lines[i]): co2_high ($(hi[i])) is below co2 ($(co2[i]))"))
        (isnan(lo[i]) || lo[i] <= co2[i]) ||
            throw(ArgumentError("$path:$(t.lines[i]): co2_low ($(lo[i])) is above co2 ($(co2[i]))"))
    end
    return ProxyData(age[idx], co2[idx], lo[idx], hi[idx], ptype[idx], ref[idx])
end

"""
    proxy_step_index(d::ProxyData, age::AbstractVector; dt = grid spacing) -> Vector{Union{Int,Nothing}}

Model time step that each observation is compared against: the step whose age `a`
satisfies `a - dt/2 ≤ obs_age < a + dt/2` (as in the R code), or `nothing` if none.
These are the bins that [`co2_windows`](@ref) pools.
"""
proxy_step_index(d::ProxyData, age::AbstractVector; dt::Real=_grid_spacing(age)) = _step_bins(d.age, age, dt)

# Model step of each observation age, with bins `a - dt/2 ≤ obs < a + dt/2` (the last
# matching step if bins overlap, as in getData.R). Shared by proxy_step_index and
# co2_windows (J-32).
function _step_bins(obs_age::AbstractVector, age::AbstractVector, dt::Real)
    (isfinite(dt) && dt > 0) || throw(ArgumentError("dt must be positive and finite, got $dt"))
    half = 0.5 * dt
    out = Vector{Union{Int,Nothing}}(nothing, length(obs_age))
    for (ii, a) in enumerate(age), j in eachindex(obs_age)
        if obs_age[j] < a + half && obs_age[j] >= a - half
            out[j] = ii
        end
    end
    return out
end

# Spacing of a uniform age grid; a single-step grid has none, so dt must then be given.
function _grid_spacing(age::AbstractVector)
    length(age) > 1 || throw(ArgumentError("a grid with one step has no spacing; pass dt explicitly"))
    return abs(age[1] - age[2])
end
