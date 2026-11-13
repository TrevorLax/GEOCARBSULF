"""
    ConstantDesign

How the constant parameters are spread over the unit hypercube.

- [`ChunkedLHS`](@ref) (default): an independent Latin hypercube for every chunk of
  samples. Memory is bounded and each chunk is stratified (improvements doc §3.3).
- [`GlobalLHS`](@ref): one Latin hypercube over all `n_sample` points, sliced into
  chunks, as in `lhs_sampling.R:33`. Memory grows as `8·n_sample·n_params` bytes
  (about 9 GB for 20 million × 56; finding F-11).
"""
abstract type ConstantDesign end

"An independent Latin hypercube per chunk (the default). See [`ConstantDesign`](@ref)."
struct ChunkedLHS <: ConstantDesign end

"A single Latin hypercube over all samples, as in the R code. See [`ConstantDesign`](@ref)."
struct GlobalLHS <: ConstantDesign end

"""
    sample_constants(rng, priors, n) -> Matrix{Float64}

`n × length(priors)` matrix of parameter values from one Latin hypercube design
transformed through the truncated priors.
"""
function sample_constants(rng::AbstractRNG, priors::AbstractVector{<:TruncatedPrior}, n::Integer)
    return transform_unit(random_lhs(rng, n, length(priors)), priors)
end

"""
    transform_unit(U, priors) -> Matrix{Float64}

Map unit-hypercube points to parameter values with [`quantile_from_unit`](@ref).
"""
function transform_unit(U::AbstractMatrix{<:Real}, priors::AbstractVector{<:TruncatedPrior})
    size(U, 2) == length(priors) || throw(ArgumentError("U has $(size(U, 2)) columns for $(length(priors)) priors"))
    X = similar(U, Float64)
    for (j, p) in enumerate(priors), i in axes(U, 1)
        X[i, j] = quantile_from_unit(p, U[i, j])
    end
    return X
end
