"""
    ConstantParams{T<:Real}

The 56 time-invariant parameters of GEOCARBSULFvolc. Field order matches the
original Fortran `Matrix_56`; see [`CONSTANT_PARAMETER_NAMES`](@ref). The meaning and
units of each field are available with [`parameter_description`](@ref) and
[`parameter_units`](@ref).

Construct by name, never by position:

```julia
p = ConstantParams(Dict(:ACT => 0.09, :ACTcarb => 0.087, ...))   # all 56 names
p = ConstantParams(names, values)                                 # any order
p2 = update(p; deltaT2X = 4.0)
```

Missing or unknown names raise an `ArgumentError`.
"""
struct ConstantParams{T<:Real}
    ACT::T
    ACTcarb::T
    VNV::T
    NV::T
    exp_NV::T
    LIFE::T
    GYM::T
    FERT::T
    exp_fnBb::T
    deltaT2X::T
    GLAC::T
    J::T
    n::T
    Ws::T
    exp_fD::T
    Fwpa_0::T
    Fwsa_0::T
    Fwga_0::T
    Fwca_0::T
    Fmg_0::T
    Fmc_0::T
    Fmp_0::T
    Fms_0::T
    Fwsi_0::T
    Xvolc_0::T
    CAPd13C_0::T
    CAPd34S_0::T
    oxygen_570::T
    Gy_570::T
    Cy_570::T
    Ca_570::T
    Ssy_570::T
    Spy_570::T
    dlsy_570::T
    dlcy_570::T
    dlpy_570::T
    dlpa_570::T
    dlgy_570::T
    dlga_570::T
    Rcy_570::T
    Rca_570::T
    Rv_570::T
    Rg_570::T
    Fob::T
    COC::T
    Ga::T
    Ssa::T
    Spa::T
    ST::T
    dlst::T
    CT::T
    dlct::T
    kwpy::T
    kwsy::T
    kwgy::T
    kwcy::T
end

_numtype(::ConstantParams{T}) where {T} = T

Base.getindex(p::ConstantParams, name::Symbol) = getfield(p, name)
Base.propertynames(::ConstantParams) = CONSTANT_PARAMETER_NAMES

"""
    ConstantParams(names::AbstractVector, values::AbstractVector)

Build from parallel lists of names (`Symbol`s or `String`s) and values, in any order.
"""
function ConstantParams(names::AbstractVector, values::AbstractVector)
    length(names) == length(values) ||
        throw(ArgumentError("got $(length(names)) names but $(length(values)) values"))
    d = Dict{Symbol,Any}()
    for (k, v) in zip(names, values)
        s = Symbol(k)
        haskey(d, s) && throw(ArgumentError("duplicate parameter name :$s"))
        d[s] = v
    end
    return ConstantParams(d)
end

"""
    ConstantParams(d::AbstractDict)
    ConstantParams(nt::NamedTuple)
    ConstantParams(; kwargs...)

Build from a mapping name → value. All 56 names in [`CONSTANT_PARAMETER_NAMES`](@ref)
must be present and no others.
"""
function ConstantParams(d::AbstractDict)
    keyset = Set(Symbol(k) for k in keys(d))
    missing_names = [n for n in CONSTANT_PARAMETER_NAMES if !(n in keyset)]
    isempty(missing_names) ||
        throw(ArgumentError("missing constant parameter(s): " * join(missing_names, ", ")))
    unknown = [k for k in keyset if !(k in CONSTANT_PARAMETER_NAMES)]
    isempty(unknown) ||
        throw(ArgumentError("unknown constant parameter(s): " * join(sort!(String.(unknown)), ", ")))
    lookup(n) = haskey(d, n) ? d[n] : d[String(n)]
    vals = [lookup(n) for n in CONSTANT_PARAMETER_NAMES]
    all(v -> v isa Real, vals) || throw(ArgumentError("all parameter values must be real numbers"))
    T = float(mapreduce(typeof, promote_type, vals))
    return ConstantParams{T}(ntuple(i -> convert(T, vals[i]), Val(N_CONSTANTS))...)
end

ConstantParams(nt::NamedTuple) = ConstantParams(Dict{Symbol,Any}(pairs(nt)))
ConstantParams(; kwargs...) = ConstantParams(Dict{Symbol,Any}(kwargs))

"""
    _constants_from_vector(T, v)

Fast constructor from a vector already in canonical order (used in the sampling loop).
"""
@inline function _constants_from_vector(::Type{T}, v::AbstractVector) where {T<:Real}
    length(v) == N_CONSTANTS ||
        throw(ArgumentError("expected $(N_CONSTANTS) values, got $(length(v))"))
    return ConstantParams{T}(ntuple(i -> convert(T, v[i]), Val(N_CONSTANTS))...)
end

"""
    parameter_vector(p::ConstantParams) -> Vector

The parameter values in the canonical order of [`CONSTANT_PARAMETER_NAMES`](@ref).
"""
parameter_vector(p::ConstantParams{T}) where {T} =
    T[getfield(p, n) for n in CONSTANT_PARAMETER_NAMES]

"""
    update(p::ConstantParams; kwargs...) -> ConstantParams

Copy of `p` with some parameters replaced, e.g. `update(p; deltaT2X = 4.0)`. The
element type is promoted if needed, so automatic-differentiation numbers can be
passed in.
"""
function update(p::ConstantParams; kwargs...)
    d = Dict{Symbol,Any}(n => getfield(p, n) for n in CONSTANT_PARAMETER_NAMES)
    for (k, v) in kwargs
        k in CONSTANT_PARAMETER_NAMES || throw(ArgumentError("unknown constant parameter :$k"))
        d[k] = v
    end
    return ConstantParams(d)
end

Base.:(==)(a::ConstantParams, b::ConstantParams) =
    all(getfield(a, n) == getfield(b, n) for n in CONSTANT_PARAMETER_NAMES)
Base.isequal(a::ConstantParams, b::ConstantParams) =
    all(isequal(getfield(a, n), getfield(b, n)) for n in CONSTANT_PARAMETER_NAMES)
Base.hash(p::ConstantParams, h::UInt) = hash(parameter_vector(p), hash(:ConstantParams, h))

function Base.show(io::IO, ::MIME"text/plain", p::ConstantParams{T}) where {T}
    println(io, "ConstantParams{$T} with $(N_CONSTANTS) parameters:")
    for n in CONSTANT_PARAMETER_NAMES
        println(io, "  ", rpad(String(n), 11), " = ", getfield(p, n))
    end
end
