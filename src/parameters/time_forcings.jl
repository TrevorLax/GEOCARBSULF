"""
    TimeForcings{T<:Real}

The 12 time-varying forcings of GEOCARBSULFvolc on a common age grid (Myr ago, strictly
decreasing, within `[0, 570]`). Fields: `age` and one vector per name in
[`TIME_FORCING_NAMES`](@ref).

Construct by name:

```julia
f = TimeForcings(age, Dict(:Sr => sr, :d13C => d13c, ...))   # all 12 names
f = TimeForcings(age; Sr = sr, d13C = d13c, ...)
f[:GEOG]                                                     # access by Symbol
```

# Examples

```jldoctest
julia> f = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv")).center;

julia> length(f.age), f.age[1], f.age[end]
(58, 570.0, 0.0)

julia> f[:GEOG] === f.GEOG
true
```

The vectors are mutable, so the samplers can overwrite them in place
([`sample_time_forcings!`](@ref)).
"""
struct TimeForcings{T<:Real}
    age::Vector{Float64}
    Sr::Vector{T}
    d13C::Vector{T}
    d34S::Vector{T}
    fR::Vector{T}
    fL::Vector{T}
    fA::Vector{T}
    fAw_fA::Vector{T}
    fD::Vector{T}
    GEOG::Vector{T}
    RT::Vector{T}
    fSR::Vector{T}
    fC::Vector{T}

    function TimeForcings{T}(age::AbstractVector{<:Real}, series::Vararg{AbstractVector,12}) where {T<:Real}
        a = collect(Float64, age)
        _check_age_grid_shape(a)
        n = length(a)
        for (name, s) in zip(TIME_FORCING_NAMES, series)
            length(s) == n || throw(ArgumentError("forcing :$name has $(length(s)) values but the age grid has $n"))
        end
        vs = map(s -> collect(T, s), series)
        return new{T}(a, vs...)
    end
end

function _check_age_grid_shape(age::Vector{Float64})
    length(age) >= 1 || throw(ArgumentError("the age grid is empty"))
    for (i, t) in enumerate(age)
        isfinite(t) || throw(ArgumentError("age[$i] = $t is not finite"))
        (0.0 <= t <= AGE_MAX) || throw(ArgumentError("age[$i] = $t is outside the model range [0, $(AGE_MAX)] Myr ago"))
        if i > 1 && !(t < age[i - 1])
            throw(ArgumentError("ages must be strictly decreasing (age[$(i-1)] = $(age[i-1]), age[$i] = $t)"))
        end
    end
    return nothing
end

"""
    TimeForcings(age, d::AbstractDict; check_finite = true)
    TimeForcings(age; check_finite = true, kwargs...)

Build from a mapping name → vector. All 12 names in [`TIME_FORCING_NAMES`](@ref) must
be present and no others. With `check_finite = true` (the default) every value must be
finite.
"""
function TimeForcings(age::AbstractVector{<:Real}, d::AbstractDict; check_finite::Bool=true)
    keyset = Set(Symbol(k) for k in keys(d))
    missing_names = [n for n in TIME_FORCING_NAMES if !(n in keyset)]
    isempty(missing_names) || throw(ArgumentError("missing time forcing(s): " * join(missing_names, ", ")))
    unknown = [k for k in keyset if !(k in TIME_FORCING_NAMES)]
    isempty(unknown) || throw(ArgumentError("unknown time forcing(s): " * join(sort!(String.(unknown)), ", ")))
    lookup(n) = haskey(d, n) ? d[n] : d[String(n)]
    series = ntuple(i -> lookup(TIME_FORCING_NAMES[i]), Val(N_FORCINGS))
    T = float(mapreduce(eltype, promote_type, series))
    f = TimeForcings{T}(age, series...)
    check_finite && _check_finite(f)
    return f
end

function TimeForcings(age::AbstractVector{<:Real}; check_finite::Bool=true, kwargs...)
    return TimeForcings(age, Dict{Symbol,Any}(kwargs); check_finite=check_finite)
end

function _check_finite(f::TimeForcings)
    for n in TIME_FORCING_NAMES
        v = getfield(f, n)
        i = findfirst(!isfinite, v)
        i === nothing || throw(ArgumentError("forcing :$n has a non-finite value at age $(f.age[i]) ($(v[i]))"))
    end
    return f
end

Base.getindex(f::TimeForcings, name::Symbol) = getfield(f, name)
Base.length(f::TimeForcings) = length(f.age)
_numtype(::TimeForcings{T}) where {T} = T

function Base.copy(f::TimeForcings{T}) where {T}
    return TimeForcings{T}(copy(f.age), (copy(getfield(f, n)) for n in TIME_FORCING_NAMES)...)
end

"""
    copyto!(dest::TimeForcings, src::TimeForcings)

Copy all forcing values of `src` into `dest` (same age grid required).
"""
function Base.copyto!(dest::TimeForcings, src::TimeForcings)
    dest.age == src.age || throw(ArgumentError("age grids differ"))
    for n in TIME_FORCING_NAMES
        copyto!(getfield(dest, n), getfield(src, n))
    end
    return dest
end

function Base.:(==)(a::TimeForcings, b::TimeForcings)
    return a.age == b.age && all(getfield(a, n) == getfield(b, n) for n in TIME_FORCING_NAMES)
end
function Base.isequal(a::TimeForcings, b::TimeForcings)
    return isequal(a.age, b.age) && all(isequal(getfield(a, n), getfield(b, n)) for n in TIME_FORCING_NAMES)
end
function Base.hash(f::TimeForcings, h::UInt)
    return foldl((acc, n) -> hash(getfield(f, n), acc), TIME_FORCING_NAMES; init=hash(f.age, hash(:TimeForcings, h)))
end

"""
    forcing_matrix(f::TimeForcings) -> Matrix

`n_time × 12` matrix with the forcings as columns in [`TIME_FORCING_NAMES`](@ref)
order (the layout of the Fortran `Matrix_12`).
"""
function forcing_matrix(f::TimeForcings{T}) where {T}
    m = Matrix{T}(undef, length(f.age), N_FORCINGS)
    for (j, n) in enumerate(TIME_FORCING_NAMES)
        m[:, j] .= getfield(f, n)
    end
    return m
end

function Base.show(io::IO, ::MIME"text/plain", f::TimeForcings{T}) where {T}
    println(io, "TimeForcings{$T} on $(length(f.age)) time steps ($(first(f.age)) → $(last(f.age)) Myr ago)")
    for n in TIME_FORCING_NAMES
        v = getfield(f, n)
        println(io, "  ", rpad(String(n), 7), " ", @sprintf("[%.4g … %.4g]", first(v), last(v)))
    end
end
