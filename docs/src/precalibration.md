# Precalibration

Precalibration keeps the parameter samples whose simulations pass through
observational *windows* often enough (Mills et al. 2019; Wong et al. 2021).

1. **Constants.** A Latin hypercube in 56 dimensions is mapped through the truncated
   priors ([`TruncatedPrior`](@ref)). With `constant_design = :chunked_lhs` (the
   default) every chunk is its own Latin hypercube. With `:global_lhs` a single design
   covers all samples, as in the R code. That uses about 9 GB at 20 million samples
   (finding F-11), and because the run usually stops early, only the first chunks of
   that design are ever evaluated.
2. **Forcings.** Each of the 12 series is drawn around its centre
   ([`InverseWishartSampler`](@ref)): Σ ~ IW(ν, (ν−p−1)·diag(σ²)), then x ~ N(μ, Σ),
   with ν from [`inverse_wishart_dof`](@ref). `fR, fL, fA, fAw_fA, fC` are then divided
   by their present-day value and `GEOG` has it subtracted.
   [`MultivariateTSampler`](@ref) draws from the same distribution (its exact
   multivariate-t marginal) in O(p) instead of O(p³).
3. **Windows.** CO2: per 10 Myr step, the envelope of `log10(co2) ± nsig·log10(co2_high/co2)`
   over the proxies in that step ([`co2_windows`](@ref)). Temperature: Mills et al.
   (2019) mean ± nsig·(max/min − mean) ([`temperature_windows`](@ref)).
4. **% outbound.** The fraction of steps outside the window; 1 if any step failed
   (CO2 = Inf) ([`legacy_percent_outbound`](@ref)).
5. **Acceptance.** [`OutboundRule`](@ref)s for CO2 and/or temperature, optionally a
   [`CretaceousWindowRule`](@ref), combined with [`AllOf`](@ref).

The engine ([`run_precalibration`](@ref)) processes chunks in parallel. Each chunk has
its own `StableRNG` seeded from `(seed, chunk)` and results are consumed in chunk
order, so a run gives the same samples on 1 or 64 threads and on any Julia version.
With `checkpoint_dir`, finished chunks are saved and reused after an interruption.
