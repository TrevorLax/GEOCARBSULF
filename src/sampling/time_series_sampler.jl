"""
    read_variance_reduction(path = datapath("variance_reduction.toml")) -> Dict{Symbol,Float64}

Variance-reduction factors `f` per forcing (`time_series_df.R:12`). They set the
inverse-Wishart degrees of freedom so that sampled variances match the reduced-variance
experiments of Royer et al. (2014).
"""
function read_variance_reduction(path::AbstractString = datapath("variance_reduction.toml"))
    d = TOML.parsefile(path)
    haskey(d, "variance_reduction") || throw(ArgumentError("$path: missing [variance_reduction] table"))
    out = Dict{Symbol,Float64}()
    for (k, v) in d["variance_reduction"]
        s = Symbol(k)
        s in TIME_FORCING_NAMES || throw(ArgumentError("$path: unknown forcing '$k'"))
        (v isa Real && 0 <= v < 1) || throw(ArgumentError("$path: factor for '$k' must be in [0, 1)"))
        out[s] = Float64(v)
    end
    missing_names = setdiff(Set(TIME_FORCING_NAMES), keys(out))
    isempty(missing_names) || throw(ArgumentError("$path: missing factors for " * join(sort!(String.(collect(missing_names))), ", ")))
    return out
end

"""
    inverse_wishart_dof(sigma::TimeForcings, f_var_red) -> Dict{Symbol,Int}

Degrees of freedom of the inverse-Wishart prior of each forcing's covariance
(`time_series_df.R:19-21`):

    ν = n_time + 3 + ceil(2·max(σ²) / (1 − f))
"""
function inverse_wishart_dof(sigma::TimeForcings, f_var_red::AbstractDict{Symbol,<:Real})
    n = length(sigma.age)
    out = Dict{Symbol,Int}()
    for name in TIME_FORCING_NAMES
        s = getfield(sigma, name)
        f = f_var_red[name]
        out[name] = n + 3 + ceil(Int, 2 * maximum(x -> x * x, s) / (1 - f))
    end
    return out
end

"""
    TimeSeriesSampler

Samplers of the 12 forcing time series around their centres. Both implementations
apply the normalisation of `lhs_sampling.R:106-112`: `fR, fL, fA, fAw_fA, fC` are
divided by their present-day value and `GEOG` has its present-day value subtracted.

- [`InverseWishartSampler`](@ref): the R algorithm. Draw Σ ~ IW(ν, (ν−p−1)·diag(σ²))
  (mean `diag(σ²)`), then x ~ N(μ, Σ). Cost O(p³) per forcing.
- [`MultivariateTSampler`](@ref): the exact marginal of the above, a multivariate t,
  drawn in O(p) (improvements doc §3.2). Identical in distribution; it cannot return
  the covariance draws.
"""
abstract type TimeSeriesSampler end

"See [`TimeSeriesSampler`](@ref)."
struct InverseWishartSampler{T} <: TimeSeriesSampler
    center::TimeForcings{T}
    sigma::TimeForcings{T}
    dof::Dict{Symbol,Int}
end

"See [`TimeSeriesSampler`](@ref)."
struct MultivariateTSampler{T} <: TimeSeriesSampler
    center::TimeForcings{T}
    sigma::TimeForcings{T}
    dof::Dict{Symbol,Int}
end

for S in (:InverseWishartSampler, :MultivariateTSampler)
    @eval function $S(center::TimeForcings{T}, sigma::TimeForcings{T}, f_var_red::AbstractDict{Symbol,<:Real}) where {T}
        center.age == sigma.age || throw(ArgumentError("centre and sigma age grids differ"))
        return $S{T}(center, sigma, inverse_wishart_dof(sigma, f_var_red))
    end
    @eval $S(prior::TimeArrayPrior, f_var_red::AbstractDict{Symbol,<:Real} = read_variance_reduction()) =
        $S(prior.center, prior.sigma, f_var_red)
end

"""
    sample_time_forcings!(rng, out::TimeForcings, sampler; covariances = nothing) -> out

Overwrite `out` with one draw of all 12 forcings. With an `InverseWishartSampler`,
`covariances` may be a `Dict{Symbol,Matrix{Float64}}` that receives the covariance draw
of each forcing.
"""
function sample_time_forcings!(rng::AbstractRNG, out::TimeForcings, s::TimeSeriesSampler; covariances = nothing)
    out.age == s.center.age || throw(ArgumentError("output and sampler age grids differ"))
    for name in TIME_FORCING_NAMES
        x = getfield(out, name)
        μ = getfield(s.center, name)
        σ = getfield(s.sigma, name)
        ν = s.dof[name]
        cov = covariances === nothing ? nothing : get!(covariances, name) do
            Matrix{Float64}(undef, length(μ), length(μ))
        end
        _draw_series!(rng, x, μ, σ, ν, s, cov)
        _normalize!(x, name)
    end
    return out
end

@inline function _normalize!(x::AbstractVector, name::Symbol)
    if name in NORMALIZE_BY_PRESENT
        x ./= x[end]
    elseif name in CENTER_AT_PRESENT
        x .-= x[end]
    end
    return x
end

# Inverse-Wishart draw by the Bartlett decomposition, then a normal draw with that
# covariance, without forming or factorising Σ:
#   W = (L A)(L A)' ~ Wishart(ν, Ψ⁻¹),  L = diag(1/√ψᵢ), A lower triangular with
#   A[i,i] = √χ²(ν−i+1) and A[i,j] ~ N(0,1) for i > j.
#   Σ = W⁻¹ ~ InverseWishart(ν, Ψ), and x = μ + (L A)⁻ᵀ z has covariance Σ.
function _draw_series!(rng::AbstractRNG, x::AbstractVector, μ, σ, ν::Int, ::InverseWishartSampler, cov)
    p = length(μ)
    ν > p + 1 || throw(ArgumentError("inverse-Wishart dof ν = $ν must exceed p + 1 = $(p + 1)"))
    M = zeros(p, p)
    @inbounds for i in 1:p
        ψ = (ν - p - 1) * σ[i]^2
        sc = 1 / sqrt(ψ)
        M[i, i] = sqrt(rand(rng, Chisq(ν - i + 1))) * sc
        for j in 1:(i-1)
            M[i, j] = randn(rng) * sc
        end
    end
    Lm = LowerTriangular(M)
    z = randn(rng, p)
    y = transpose(Lm) \ z
    @inbounds for i in 1:p
        x[i] = μ[i] + y[i]
    end
    if cov !== nothing
        Minv = inv(Lm)
        cov .= transpose(Minv) * Minv
    end
    return x
end

# Multivariate-t draw: x = μ + σ ⊙ z · √((ν − p − 1)/u), u ~ χ²(ν − p + 1).
function _draw_series!(rng::AbstractRNG, x::AbstractVector, μ, σ, ν::Int, ::MultivariateTSampler, cov)
    cov === nothing || throw(ArgumentError("MultivariateTSampler cannot return covariance draws"))
    p = length(μ)
    ν > p + 1 || throw(ArgumentError("inverse-Wishart dof ν = $ν must exceed p + 1 = $(p + 1)"))
    u = rand(rng, Chisq(ν - p + 1))
    scale = sqrt((ν - p - 1) / u)
    @inbounds for i in 1:p
        x[i] = μ[i] + σ[i] * randn(rng) * scale
    end
    return x
end
