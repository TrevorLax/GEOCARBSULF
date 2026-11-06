"""
    climate_sensitivity_summary(res; probs = (0.05, 0.5, 0.95), exceed = (6.0, 7.0)) -> NamedTuple

The headline numbers of Wong et al. (2021): quantiles of ΔT2x, GLAC and the glacial
sensitivity ΔT2x·GLAC, and `Pr(ΔT2x ≥ x)` for each `x` in `exceed`.
"""
function climate_sensitivity_summary(res::PrecalibrationResult; probs = (0.05, 0.5, 0.95), exceed = (6.0, 7.0))
    n_accepted(res) >= 1 || throw(ArgumentError("the result has no accepted samples"))
    s = constant_column(res, :deltaT2X)
    g = constant_column(res, :GLAC)
    p = collect(Float64, probs)
    return (
        probs = p,
        deltaT2X = Statistics.quantile(s, p),
        GLAC = Statistics.quantile(g, p),
        deltaT2X_glacial = Statistics.quantile(s .* g, p),
        prob_exceed = Dict(x => count(>=(x), s) / length(s) for x in exceed),
        n = length(s),
    )
end

"""
    linear_interpolator(x, y) -> function

Piecewise-linear interpolation through `(x, y)`, returning `NaN` outside
`[minimum(x), maximum(x)]` (R's `approxfun` with `rule = 1`). Used for the Park &
Royer (2011) ΔT2x distribution.
"""
function linear_interpolator(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    length(x) == length(y) || throw(ArgumentError("x and y differ in length"))
    length(x) >= 2 || throw(ArgumentError("need at least two points"))
    o = sortperm(x)
    xs = Float64.(x[o]); ys = Float64.(y[o])
    return function (q::Real)
        (q < xs[1] || q > xs[end] || isnan(q)) && return NaN
        i = searchsortedlast(xs, q)
        i >= length(xs) && return ys[end]
        xs[i+1] == xs[i] && return ys[i]
        w = (q - xs[i]) / (xs[i+1] - xs[i])
        return ys[i] + w * (ys[i+1] - ys[i])
    end
end
