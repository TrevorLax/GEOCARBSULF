"Quantile levels used throughout the analysis scripts (`analysis_and_plots.R:46`)."
const DEFAULT_PROBS = [0.0, 0.025, 0.05, 0.25, 0.5, 0.75, 0.95, 0.975, 1.0]

"""
    subsample_indices(n_available, n; rng = StableRNG(1)) -> Vector{Int}

`n` sample indices: without replacement if enough samples exist, otherwise with
replacement (`analysis_and_plots.R:84-88`). `n = nothing` keeps all samples in order.
"""
function subsample_indices(n_available::Integer, n; rng::AbstractRNG=StableRNG(1))
    n === nothing && return collect(1:n_available)
    n_available >= 1 || throw(ArgumentError("no samples available"))
    return n_available >= n ? Random.randperm(rng, n_available)[1:n] : rand(rng, 1:n_available, n)
end

"""
    parameter_quantiles(res; probs = DEFAULT_PROBS, n = nothing, rng = StableRNG(1))
        -> (names, probs, values)

Quantiles of every accepted constant parameter, plus the derived glacial sensitivity
`:deltaT2Xglac = deltaT2X·GLAC` as the last row. `values[i, j]` is the `probs[j]`
quantile of `names[i]`. With `n`, a subsample of `n` accepted samples is used, as the R
analysis did to compare experiments of different sizes.
"""
function parameter_quantiles(res::PrecalibrationResult; probs=DEFAULT_PROBS, n=nothing, rng::AbstractRNG=StableRNG(1))
    n_accepted(res) >= 1 || throw(ArgumentError("the result has no accepted samples"))
    idx = subsample_indices(n_accepted(res), n; rng=rng)
    names = vcat(res.constant_names, :deltaT2Xglac)
    vals = Matrix{Float64}(undef, length(names), length(probs))
    for (i, nm) in enumerate(res.constant_names)
        vals[i, :] .= Statistics.quantile(res.constants[idx, i], probs)
    end
    glac = constant_column(res, :deltaT2X)[idx] .* constant_column(res, :GLAC)[idx]
    vals[end, :] .= Statistics.quantile(glac, probs)
    return (names=names, probs=collect(Float64, probs), values=vals)
end

"""
    time_series_quantiles(res; probs = DEFAULT_PROBS) -> Array{Float64,3}

`n_time × length(probs) × 12` quantiles of the accepted forcing series.
"""
function time_series_quantiles(res::PrecalibrationResult; probs=DEFAULT_PROBS)
    nt, _, nf = size(res.time_series)
    q = Array{Float64,3}(undef, nt, length(probs), nf)
    for j in 1:nf, t in 1:nt
        q[t, :, j] .= Statistics.quantile(view(res.time_series, t, :, j), probs)
    end
    return q
end

"""
    row_quantiles(M; probs = DEFAULT_PROBS) -> Matrix{Float64}

Quantiles of every row of `M`, ignoring `NaN` (rows that are all `NaN` give `NaN`).
`±Inf` values are kept, as in R's `quantile`.
"""
function row_quantiles(M::AbstractMatrix{<:Real}; probs=DEFAULT_PROBS)
    out = fill(NaN, size(M, 1), length(probs))
    for i in axes(M, 1)
        v = filter(!isnan, collect(view(M, i, :)))
        isempty(v) || (out[i, :] .= Statistics.quantile(v, probs))
    end
    return out
end

"""
    prior_posterior_table(table::PriorTable, res; probs = (0.05, 0.95)) -> NamedTuple

Prior mean and 5–95 % range against posterior median and 5–95 % range for every
calibrated constant (`som_parameters_table.csv`, `analysis_and_plots.R:485-537`). The
prior quantiles are those of the truncated priors.
"""
function prior_posterior_table(table::PriorTable, res::PrecalibrationResult; probs=(0.05, 0.95))
    specs = calibrated_specs(table)
    lo, hi = probs
    name = Symbol[]
    prior_mean = Float64[]
    prior_lo = Float64[]
    prior_hi = Float64[]
    post_med = Float64[]
    post_lo = Float64[]
    post_hi = Float64[]
    for s in specs
        pr = TruncatedPrior(s)
        x = constant_column(res, s.name)
        push!(name, s.name)
        push!(prior_mean, s.mean)
        push!(prior_lo, quantile_from_unit(pr, lo))
        push!(prior_hi, quantile_from_unit(pr, hi))
        q = Statistics.quantile(x, [0.5, lo, hi])
        push!(post_med, q[1])
        push!(post_lo, q[2])
        push!(post_hi, q[3])
    end
    return (
        parameter=name,
        prior_mean=prior_mean,
        prior_lower=prior_lo,
        prior_upper=prior_hi,
        posterior_median=post_med,
        posterior_lower=post_lo,
        posterior_upper=post_hi,
    )
end
