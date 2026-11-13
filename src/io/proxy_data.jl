"Proxy types assimilated by default (`model_setup.R:11-15`)."
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
other columns are ignored) and keep the listed proxy types. As in `getData.R:12-20`,
rows are grouped by proxy type in the order of `proxies`.
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
        (co2[i] > 0 && hi[i] > 0) || throw(ArgumentError("$path: row $(i + 1): co2 and co2_high must be positive"))
    end
    return ProxyData(age[idx], co2[idx], lo[idx], hi[idx], ptype[idx], ref[idx])
end

"""
    proxy_step_index(d::ProxyData, age::AbstractVector) -> Vector{Union{Int,Nothing}}

Model time step that each observation is compared against: the step whose age `a`
satisfies `a - dt/2 ≤ obs_age < a + dt/2` (`getData.R:28-35`), or `nothing` if none.
"""
function proxy_step_index(d::ProxyData, age::AbstractVector)
    dt = length(age) > 1 ? abs(age[1] - age[2]) : 10.0
    out = Vector{Union{Int,Nothing}}(nothing, length(d.age))
    for (ii, a) in enumerate(age), j in eachindex(d.age)
        if d.age[j] < a + 0.5 * dt && d.age[j] >= a - 0.5 * dt
            out[j] = ii
        end
    end
    return out
end
