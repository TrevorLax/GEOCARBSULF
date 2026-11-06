# Porting notes

This page records how the R/Fortran code maps onto the Julia package and every
decision that makes the two differ. Finding numbers (F-xx) refer to
`JULIA_IMPROVEMENTS_AND_FRAMEWORKS.md`; decision numbers (D-x) to §9 of
`JULIA_REWRITE_PLAN.md`.

## File mapping

| R / Fortran | Julia |
|:--|:--|
| `fortran/src/run_geocarb.f90` | `src/model/*.jl` ([`run_geocarb`](@ref)) |
| `fortran/src/run_geocarb_supp.f90` | the same code with [`ModelOptions`](@ref) |
| `run_geocarbF.R`, `run_geocarb_suppF.R`, `model_run*.R` | removed: no FFI, no index reordering |
| `parameterSetup.R` | [`read_prior_table`](@ref), [`read_time_arrays`](@ref), `src/parameters/names.jl` |
| `model_setup.R`, `getData.R` | [`ExperimentConfig`](@ref), [`read_proxy_data`](@ref) |
| `constraints.R`, `percent_outbound.R` | [`co2_windows`](@ref), [`temperature_windows`](@ref), [`legacy_percent_outbound`](@ref) |
| `time_series_df.R` | [`inverse_wishart_dof`](@ref), `data/variance_reduction.toml` |
| `lhs*.R`, `lhs_sampling*.R` | [`run_precalibration`](@ref), [`AcceptanceRule`](@ref)s |
| `lhs_driver*.R`, `run_experiment.R` | `experiments/**/*.toml`, `scripts/run_experiment.jl` |
| `analysis_and_plots.R` | `src/analysis/*.jl`, `ext/GeocarbMakieExt.jl`, `scripts/analysis_main.jl` |
| `analysis_supplemental_experiments.R` | `scripts/analysis_supplemental.jl` |
| `cretaceous_experiment.R` | `scripts/analysis_cretaceous.jl`, `experiments/cretaceous/stage2.toml` |
| `install_packages.R` | `Project.toml` |

The untouched originals are kept in `legacy/` as the test oracle until parity is signed off.

## Decisions adopted (plan §9, proposed defaults)

| | decision | implementation |
|:--|:--|:--|
| D1 | keep known quirks for parity; fixes are opt-in | `fortran_single_literals = true` (F-05, the v1 default); `corrected_newton_derivative = false` (F-01); per-step failure semantics (F-08); /31 and 381 blend weights (F-10) |
| D2 | Cretaceous stage 1 runs on the time-array centres | `run_on_time_centers = true` in `experiments/cretaceous/*.toml` (F-02) |
| D3 | Cretaceous step at 90 Ma | `cretaceous_age = 90.0` (F-03); selected by age, not index |
| D4 | temperature-only experiments may accept failed runs | `reject_failed_runs = false` by default (F-04) |
| D5 | chunked Latin hypercube | `constant_design = :chunked_lhs` (default); `:global_lhs` for the R design |
| D6 | do not store covariance draws | `save_covariances = false`; `sample_keys` identify every sample |
| D7 | JLD2 results plus CSV summaries | [`save_result`](@ref), [`write_summary_csvs`](@ref) |
| D8 | single package | `GeocarbPrecalibration.jl`; the model core does not depend on the workflow |
| D9 | GPL-3.0-or-later | `LICENSE` copied from the original |

## Deliberate differences from the R/Fortran code

- **Literal precision (F-05).** The compiled Fortran uses single-precision values of
  `0.01, 0.9, 0.2, 0.7, 0.6, 0.8, 1.2` and `log(2.0)`. Version 1 reproduces them by
  default (`fortran_single_literals = true`), so this is *not* a difference unless you
  opt out. With `false`, every literal is Float64; on the 1000-sample legacy
  comparison that changes the pass/fail outcome of 101 runs and CO2 by up to 14 % in
  otherwise valid steps, so treat it as a model change, not a precision improvement.
- **Last-bit rounding of `exp`, `log` and `^`.** Julia's maths library and the C
  runtime gfortran links against round differently now and then. Valid steps agree
  to about 4e-9 relative; after a run's first failed step the legacy model keeps
  integrating from an invalid state (F-08) and the difference grows to about 1e-6.
  The tests therefore use `rtol = 1e-8` before and `1e-4` after the first failure
  (see [Testing](testing.md)).
- **NaN instead of exceptions.** Powers and logarithms of negative numbers give NaN as
  in Fortran (`nanpow`, `nanlog`), never a `DomainError`.
- **`gym_factor = 0`** is well defined (the Fortran divides by it; F-09).
- **ΔT2x ramp** is off unless `dT2X_ramp = true`. The R default
  `supp_experiment_parameters = c(130, 80, 1, 1)` silently switched it on (F-09).
- **Random numbers.** Julia uses `StableRNG` streams per chunk, so individual samples
  differ from R's. Constants come from a Latin hypercube per chunk by default (D5).
- **Single chunk.** `n_sample ≤ n_per_chunk` works (a stub in R, F-12).
- **Cretaceous stage 2.** The forcing centres are the mean accepted series of stage 1,
  matched by name. In R, `par_time_mean_cret.csv` was written with row names and read
  back with `read.csv`, which adds an `X` column, so every forcing shifted by one
  column and `Sr` became `1, 2, …, 58` (**F-27**, found during the port). Please
  check whether the published stage-2 results were affected.
- **Seeds.** `lhs_sampling_cret.R` overrode the driver seed with `set.seed(2021)`
  (F-18); in Julia the seed comes only from the configuration.
- **Analysis.** The duplicated `deltaT2Xglac` row and quantiles of placeholder zeros
  (F-17) are not reproduced. Hindcasts reuse saved outputs. Numbers are written to
  `numbers.toml` instead of being printed.

## Not ported (yet)

- Reading the legacy `.RData` outputs (`RData.jl` could be added as a package extension).
- Seven of the seventeen R figures (KDE panels of every parameter, sample-size
  convergence, the supplemental hindcast grid, Cretaceous panels). The numbers behind
  them are available from `src/analysis`.
- The `PR2011` and `LENTON` time-array files and the `PR2011` prior file are not in the
  repository (F-14). The configuration accepts them once they are added to `data/`.
