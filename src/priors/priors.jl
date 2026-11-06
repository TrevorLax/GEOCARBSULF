"""
    TruncatedPrior

Prior of one constant parameter: an untruncated `base` distribution (Normal, LogNormal
or Uniform) restricted to `[lower, upper]`. `cdf_lower` and `cdf_upper` are the base
CDF values at the bounds.

Samples are drawn exactly as in `lhs_sampling.R:39-65`: a uniform `u` is rescaled into
`[cdf_lower, cdf_upper]` and mapped through the base quantile function (see
[`quantile_from_unit`](@ref)).
"""
struct TruncatedPrior{D<:Distributions.UnivariateDistribution}
    name::Symbol
    base::D
    lower::Float64
    upper::Float64
    cdf_lower::Float64
    cdf_upper::Float64
end

"""
    TruncatedPrior(s::PriorSpec)

Prior of a constant parameter from its CSV row. Gaussian: `Normal(mean, two_sigma/2)`.
Log-normal: `LogNormal(log(mean), log(two_sigma/2))`. Uniform: `Uniform(lower, upper)`.
"""
function TruncatedPrior(s::PriorSpec)
    s.kind == :constant || throw(ArgumentError("priors are only built for constant parameters (:$(s.name))"))
    base = if s.distribution == :gaussian
        Normal(s.mean, 0.5 * s.two_sigma)
    elseif s.distribution == :lognormal
        LogNormal(log(s.mean), log(0.5 * s.two_sigma))
    else
        Uniform(s.lower, s.upper)
    end
    return TruncatedPrior(s.name, base, s.lower, s.upper,
        Distributions.cdf(base, s.lower), Distributions.cdf(base, s.upper))
end

"""
    quantile_from_unit(p::TruncatedPrior, u) -> x

Map `u ∈ (0, 1)` to a parameter value: `quantile(base, u·(F(upper) − F(lower)) + F(lower))`.
"""
@inline quantile_from_unit(p::TruncatedPrior, u::Real) =
    Distributions.quantile(p.base, u * (p.cdf_upper - p.cdf_lower) + p.cdf_lower)

"""
    quantile_from_cdf(p::TruncatedPrior, q) -> x

Base quantile at an already-rescaled probability `q ∈ [F(lower), F(upper)]` (the
`parameters_lhs` values of the R code).
"""
@inline quantile_from_cdf(p::TruncatedPrior, q::Real) = Distributions.quantile(p.base, q)

"""
    truncated_distribution(p::TruncatedPrior)

The equivalent `Distributions.truncated` object (useful for densities and tests).
"""
truncated_distribution(p::TruncatedPrior) = Distributions.truncated(p.base, p.lower, p.upper)

"""
    prior_pdf(p::TruncatedPrior, x) -> Float64

Density of the truncated prior at `x`.
"""
prior_pdf(p::TruncatedPrior, x::Real) = Distributions.pdf(truncated_distribution(p), x)

"""
    build_priors(t::PriorTable) -> Vector{TruncatedPrior}

Priors of the calibrated constant parameters, in file order.
"""
build_priors(t::PriorTable) = [TruncatedPrior(s) for s in calibrated_specs(t)]
