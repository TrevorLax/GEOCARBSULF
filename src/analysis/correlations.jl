"""
    correlation_screen(res, target::AbstractVector; method = :spearman) -> NamedTuple

Correlation of `target` (one value per accepted sample, for example the temperature
at 100 Ma or ΔT2x) with every constant parameter, sorted by decreasing magnitude
(`analysis_and_plots.R:553-656`). Returns `(names, r)`.
"""
function correlation_screen(res::PrecalibrationResult, target::AbstractVector{<:Real}; method::Symbol=:spearman)
    length(target) == n_accepted(res) || throw(ArgumentError("target must have one value per accepted sample"))
    corf = if method == :spearman
        StatsBase.corspearman
    elseif method == :pearson
        Statistics.cor
    else
        throw(ArgumentError("method must be :spearman or :pearson"))
    end
    r = [corf(res.constants[:, j], target) for j in axes(res.constants, 2)]
    o = sortperm(abs.(r); rev=true)
    return (names=res.constant_names[o], r=r[o])
end

"""
    acf_quantiles(res; lag_max = 10, probs = DEFAULT_PROBS) -> Array{Float64,3}

Quantiles across accepted samples of the autocorrelation function of each forcing
series: `(lag_max + 1) × length(probs) × 12` (`analysis_and_plots.R:660-707`).
"""
function acf_quantiles(res::PrecalibrationResult; lag_max::Integer=10, probs=DEFAULT_PROBS)
    nt, n, nf = size(res.time_series)
    lag_max < nt || throw(ArgumentError("lag_max must be smaller than the number of time steps"))
    lags = 0:lag_max
    out = Array{Float64,3}(undef, length(lags), length(probs), nf)
    acf = Matrix{Float64}(undef, length(lags), n)
    for j in 1:nf
        for k in 1:n
            acf[:, k] .= StatsBase.autocor(res.time_series[:, k, j], lags)
        end
        for l in eachindex(lags)
            v = filter(!isnan, acf[l, :])
            out[l, :, j] .= isempty(v) ? NaN : Statistics.quantile(v, probs)
        end
    end
    return out
end

"""
    survival_curve(x) -> (x = sorted values, survival = 1 − ecdf)

Empirical survival function with `ecdf = (1:n)/(n + 1)` (`analysis_supplemental_experiments.R:244-252`).
"""
function survival_curve(x::AbstractVector{<:Real})
    v = sort(filter(!isnan, collect(Float64, x)))
    n = length(v)
    return (x=v, survival=1 .- (1:n) ./ (n + 1))
end
