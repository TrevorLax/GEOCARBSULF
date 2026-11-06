"""
    TimeArrayPrior{T}

Centres and standard deviations of the 12 time-varying forcings, both as
[`TimeForcings`](@ref) on the same age grid.
"""
struct TimeArrayPrior{T<:Real}
    center::TimeForcings{T}
    sigma::TimeForcings{T}
end

"Forcings replaced by their `_Godderis` columns when `use_godderis = true` (`parameterSetup.R:46`)."
const GODDERIS_FORCINGS = (:fA, :fAw_fA, :fD, :GEOG)

"""
    read_time_arrays(path; use_godderis = true) -> TimeArrayPrior{Float64}

Read a `GEOCARB_input_arrays_*.csv` file: an `age` column and, for each forcing `X`,
a centre column `X` and a standard-deviation column `eX`. This reproduces
`parameterSetup.R:34-85`:

1. with `use_godderis = true` (the R default `l_Godderis <- TRUE`), `fA, fAw_fA, fD,
   GEOG` and their errors are taken from the `*_Godderis` columns (Goddéris et al.
   2012);
2. the centre of `fAw_fA` is divided by its present-day value (Krause et al. 2018);
   its standard deviation is *not* rescaled, as in the R code.

The file must list ages from oldest to youngest.
"""
function read_time_arrays(path::AbstractString; use_godderis::Bool = true)
    t = read_csv_table(path)
    age = numeric_column(t, "age")
    center = Dict{Symbol,Vector{Float64}}()
    sigma = Dict{Symbol,Vector{Float64}}()
    for name in TIME_FORCING_NAMES
        cname = String(name)
        ename = "e" * cname
        if use_godderis && name in GODDERIS_FORCINGS
            cname *= "_Godderis"
            ename *= "_Godderis"
        end
        center[name] = numeric_column(t, cname)
        sigma[name] = numeric_column(t, ename)
    end
    present = center[:fAw_fA][end]
    (isfinite(present) && present != 0) ||
        throw(ArgumentError("$path: present-day fAw_fA must be finite and non-zero to normalise it"))
    center[:fAw_fA] = center[:fAw_fA] ./ present
    for (name, v) in sigma
        any(x -> !(x > 0) || !isfinite(x), v) &&
            throw(ArgumentError("$path: standard deviations of :$name must be positive and finite"))
    end
    return TimeArrayPrior(TimeForcings(age, center), TimeForcings(age, sigma))
end

"""
    mean_time_forcings(series::AbstractArray{<:Real,3}, age) -> TimeForcings

Mean forcings from an `n_time × n_samples × 12` array (forcings in
[`TIME_FORCING_NAMES`](@ref) order), for example the accepted series of a previous
experiment. This is what the two-stage Cretaceous experiment uses as new centres (the R
version, `par_time_mean_cret.csv`, is affected by finding F-27).
"""
function mean_time_forcings(series::AbstractArray{<:Real,3}, age::AbstractVector)
    size(series, 3) == N_FORCINGS || throw(ArgumentError("expected $(N_FORCINGS) forcings in dimension 3"))
    size(series, 2) >= 1 || throw(ArgumentError("no samples to average"))
    d = Dict{Symbol,Vector{Float64}}()
    for (j, n) in enumerate(TIME_FORCING_NAMES)
        d[n] = vec(mean(view(series, :, :, j); dims = 2))
    end
    return TimeForcings(age, d)
end
