"""
    PriorSpec

One row of a `GEOCARB_input_summaries_calib_*.csv` file.

| field | meaning |
|:--|:--|
| `name` | parameter or forcing name |
| `kind` | `:constant` or `:time_array` |
| `distribution` | `:gaussian`, `:lognormal` or `:uniform` |
| `mean`, `two_sigma` | location and spread. For `:gaussian`, σ = `two_sigma/2`. For `:lognormal`, `meanlog = log(mean)` and `sdlog = log(two_sigma/2)`, so `two_sigma` is a *multiplicative* factor (`lhs_sampling.R:58`). |
| `lower`, `upper` | truncation bounds (`±Inf` allowed; `_inf` in the file means `-Inf`) |
| `calibrate` | `calib == 1`: sampled; otherwise fixed at `mean` |
| `resample` | the `resample` column, kept for completeness |
"""
struct PriorSpec
    name::Symbol
    kind::Symbol
    distribution::Symbol
    mean::Float64
    two_sigma::Float64
    lower::Float64
    upper::Float64
    calibrate::Bool
    resample::Bool
end

"""
    PriorTable

All rows of a prior-summary CSV, with lookup by name ([`spec`](@ref)).
"""
struct PriorTable
    source::String
    specs::Vector{PriorSpec}
end

const _PRIOR_COLUMNS = ("parameter", "type", "resample", "distribution_type", "mean",
                        "two_sigma", "lower_limit", "upper_limit", "calib")

"""
    read_prior_table(path) -> PriorTable

Read and validate a prior-summary CSV (`GEOCARB_input_summaries_calib_all.csv`).
The file must contain exactly the 56 constants of [`CONSTANT_PARAMETER_NAMES`](@ref)
and the 12 time arrays of [`TIME_FORCING_NAMES`](@ref), in any order.
"""
function read_prior_table(path::AbstractString)
    t = read_csv_table(path)
    for c in _PRIOR_COLUMNS
        has_column(t, c) || throw(ArgumentError("$path: required column '$c' not found"))
    end
    names = column(t, "parameter")
    types = column(t, "type")
    dist = column(t, "distribution_type")
    resample = column(t, "resample")
    calib = column(t, "calib")
    specs = PriorSpec[]
    for r in eachindex(names)
        where_ = "$path: row $(r + 1) ($(names[r]))"
        kind = types[r] == "constant" ? :constant :
               types[r] == "time array" ? :time_array :
               throw(ArgumentError("$where_: unknown type '$(types[r])' (expected 'constant' or 'time array')"))
        d = Symbol(lowercase(dist[r]))
        d in (:gaussian, :lognormal, :uniform) ||
            throw(ArgumentError("$where_: unknown distribution_type '$(dist[r])'"))
        num(col) = try
            parse_number(t.rows[r][_colindex(t, col)]; allow_missing = true)
        catch err
            err isa ArgumentError || rethrow()
            throw(ArgumentError("$where_, column '$col': $(err.msg)"))
        end
        μ = num("mean"); s2 = num("two_sigma"); lo = num("lower_limit"); hi = num("upper_limit")
        isnan(lo) && (lo = -Inf)
        isnan(hi) && (hi = Inf)
        lo < hi || throw(ArgumentError("$where_: lower_limit ($lo) must be smaller than upper_limit ($hi)"))
        if kind == :constant
            isfinite(μ) || throw(ArgumentError("$where_: mean must be finite"))
            if d == :gaussian
                (isfinite(s2) && s2 > 0) || throw(ArgumentError("$where_: two_sigma must be positive"))
            elseif d == :lognormal
                μ > 0 || throw(ArgumentError("$where_: a log-normal prior needs mean > 0"))
                (isfinite(s2) && s2 / 2 > 1) ||
                    throw(ArgumentError("$where_: a log-normal prior needs two_sigma/2 > 1 (sdlog = log(two_sigma/2))"))
            else
                (isfinite(lo) && isfinite(hi)) ||
                    throw(ArgumentError("$where_: a uniform prior needs finite bounds"))
            end
        end
        cal = strip(calib[r])
        cal in ("0", "1") || throw(ArgumentError("$where_: calib must be 0 or 1, got '$cal'"))
        rs = uppercase(strip(resample[r]))
        push!(specs, PriorSpec(Symbol(names[r]), kind, d, μ, s2, lo, hi, cal == "1", rs in ("TRUE", "1", "T")))
    end
    table = PriorTable(String(path), specs)
    _validate_prior_names(table)
    return table
end

function _validate_prior_names(t::PriorTable)
    seen = Set{Symbol}()
    for s in t.specs
        s.name in seen && throw(ArgumentError("$(t.source): duplicate parameter '$(s.name)'"))
        push!(seen, s.name)
    end
    consts = Set(s.name for s in t.specs if s.kind == :constant)
    times = Set(s.name for s in t.specs if s.kind == :time_array)
    miss_c = setdiff(Set(CONSTANT_PARAMETER_NAMES), consts)
    extra_c = setdiff(consts, Set(CONSTANT_PARAMETER_NAMES))
    miss_t = setdiff(Set(TIME_FORCING_NAMES), times)
    extra_t = setdiff(times, Set(TIME_FORCING_NAMES))
    msg = String[]
    isempty(miss_c) || push!(msg, "missing constants: " * join(sort!(String.(collect(miss_c))), ", "))
    isempty(extra_c) || push!(msg, "unknown constants: " * join(sort!(String.(collect(extra_c))), ", "))
    isempty(miss_t) || push!(msg, "missing time arrays: " * join(sort!(String.(collect(miss_t))), ", "))
    isempty(extra_t) || push!(msg, "unknown time arrays: " * join(sort!(String.(collect(extra_t))), ", "))
    isempty(msg) || throw(ArgumentError("$(t.source): " * join(msg, "; ")))
    return nothing
end

"""
    spec(t::PriorTable, name::Symbol) -> PriorSpec
"""
function spec(t::PriorTable, name::Symbol)
    i = findfirst(s -> s.name == name, t.specs)
    i === nothing && throw(ArgumentError("parameter :$name not in $(t.source)"))
    return t.specs[i]
end

"Constant-parameter rows, in file order."
constant_specs(t::PriorTable) = [s for s in t.specs if s.kind == :constant]

"Constant-parameter rows that are calibrated (`calib == 1`), in file order."
calibrated_specs(t::PriorTable) = [s for s in t.specs if s.kind == :constant && s.calibrate]

"""
    mean_constants(t::PriorTable) -> ConstantParams{Float64}

All constants at their prior means (the "preliminary simulation" of `lhs.R:30`).
"""
mean_constants(t::PriorTable) =
    ConstantParams(Dict{Symbol,Any}(s.name => s.mean for s in constant_specs(t)))
