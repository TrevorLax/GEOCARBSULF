# Porting notes

This page records how the R/Fortran code maps onto the Julia package and every
decision that makes the two differ. Finding numbers (F-xx) refer to the review of the
original code carried out before the port, and decision numbers (D-x) to the porting
decisions taken from it (internal planning documents, not distributed). Each finding
used in the code is described where it is cited.

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

## Where each function comes from

Line numbers refer to the files in `legacy/` (`fortran/src/run_geocarb.f90` unless noted
otherwise). They are kept here rather than in the docstrings, so that the API
documentation describes behaviour only and this table is the one place to update.

| Julia | Fortran (`run_geocarb.f90`) | R |
|:--|:--|:--|
| [`run_geocarb`](@ref), [`run_geocarb!`](@ref) | whole file; `run_geocarb_supp.f90` through [`ModelOptions`](@ref) | `run_geocarbF.R`, `run_geocarb_suppF.R` |
| [`ModelOptions`](@ref): `dt` | 273 (`Dt`) | |
| [`ModelOptions`](@ref): `glacial_intervals` | 309 | |
| [`ModelOptions`](@ref): `gym_angio_transition`, `gym_factor`, `dT2X_ramp` | `run_geocarb_supp.f90` (`age_gym_ang_beg/end`, `gym_fac`, `dT2X_fac`) | `supp_experiment_parameters` |
| [`ModelOptions`](@ref): `iteration_threshold` | | `parameterSetup.R:15` |
| [`ModelOptions`](@ref): `convergence_tol`, `newton_damping`, `newton_shrink` | 435, 450, 452 | |
| [`ModelOptions`](@ref): `rco2_bounds` | 524 | |
| [`ModelOptions`](@ref): `present_day_o2_percent`, `present_day_rco2` | 561, 562 | |
| `AGE_MAX` (solar term `Ws*t/570`) | throughout | |
| `PLEISTOCENE_CO2_PPM` | 549 | |
| `O2_MASS_PRESENT` | 274 (`oxygen_0`) | |
| `O2_PERCENT_CONSTANT` | 550 | |
| `PRESENT_TEMPERATURE` (T0) | | `lhs_sampling.R:137` |
| `RCO2_INITIAL` | 276 | |
| `PYRITE_O2_RATIO` | 404 | |
| `SR_SCALE`, `SR_OFFSET` | 393 | |
| `AGE_VASCULAR_RAMP_START`, `AGE_GYMNOSPERM`, `VASCULAR_RAMP_LENGTH` | 319–346 | |
| `BLEND_DENOMINATOR`, `BLEND_UPPER` | 479–480 | |
| `in_glacial_interval`, `gcm_factor` | 309; ramp: `run_geocarb_supp.f90:324-336` | |
| `vegetation_fE` | 319–359; `run_geocarb_supp.f90:374-395` | |
| `carbonate_fBB` | 325, 336–343 | |
| `source_fluxes` | 363–378 | |
| `isotope_fractionations` | 381–382 | |
| `burial_fluxes` | 383–390 | |
| `volcanic_weathering`, `volcanic_weathering_factor` | 393–400 | |
| `update_oxygen` | 403–405 | |
| `silicate_weathering_no_climate` | 416 | |
| `solve_rco2` | 418–521 | |
| `ReservoirState`, `initial_state`, `update_reservoirs` | 279–294, 529–545 | |
| [`StepStatus`](@ref) | 524 (`RCO2OutOfRange`), 561 (`PresentDayCheckFailed`) | |
| [`surface_temperature`](@ref) | 556 (`temp_out`) | `lhs_sampling.R:137`; hindcasts `analysis_and_plots.R:140` |
| [`TIME_FORCING_NAMES`](@ref) | `Matrix_12` | column permutation `parameterSetup.R:202` |
| `NORMALIZE_BY_PRESENT`, `CENTER_AT_PRESENT` | | `lhs_sampling.R:106-112` |
| [`read_time_arrays`](@ref), `GODDERIS_FORCINGS` | | `parameterSetup.R:34-85` (Goddéris columns: line 46) |
| [`mean_constants`](@ref) | | `lhs.R:30` |
| `PriorSpec` (log-normal spread) | | `lhs_sampling.R:58` |
| [`TruncatedPrior`](@ref), [`quantile_from_unit`](@ref) | | `lhs_sampling.R:39-65` |
| [`GlobalLHS`](@ref) | | `lhs_sampling.R:33` |
| [`read_variance_reduction`](@ref) | | `time_series_df.R:12` |
| [`inverse_wishart_dof`](@ref) | | `time_series_df.R:19-21` |
| [`TimeSeriesSampler`](@ref) | | `lhs_sampling.R:106-112` (normalisation) |
| `DEFAULT_PROXIES` | | `model_setup.R:11-15` |
| [`read_proxy_data`](@ref) | | `getData.R:12-20` |
| `proxy_step_index` | | `getData.R:28-35` |
| [`read_temperature_data`](@ref) | | `constraints.R:52` |
| [`co2_windows`](@ref) | | `constraints.R:28-43` |
| [`temperature_windows`](@ref) | | `constraints.R:51-71` |
| `shift` | | `constraints.R:72-73` |
| [`legacy_percent_outbound`](@ref) | | `percent_outbound.R` |
| [`OutboundRule`](@ref) | | `lhs_sampling.R:150-163` |
| [`CretaceousWindowRule`](@ref) | | `lhs_sampling_cret.R:136-140` |
| [`load_experiments`](@ref) | | `expand.grid` in `lhs_driver.R` |
| [`merge_results`](@ref) | | `analysis_and_plots.R:61-77` |
| `DEFAULT_PROBS` | | `analysis_and_plots.R:46` |
| `subsample_indices` | | `analysis_and_plots.R:84-88` |
| [`prior_posterior_table`](@ref) | | `analysis_and_plots.R:485-537` |
| [`correlation_screen`](@ref) | | `analysis_and_plots.R:553-656` |
| [`acf_quantiles`](@ref) | | `analysis_and_plots.R:660-707` |
| [`survival_curve`](@ref) | | `analysis_supplemental_experiments.R:244-252` |

Code comments inside function bodies still cite Fortran lines next to the expressions
they reproduce; they are notes for maintainers and do not appear in the documentation.

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
  comparison that switches 101 time steps (summed over the 1000 runs) between valid
  and failed and moves CO2 by up to 14 % in otherwise valid steps, so treat it as a
  model change, not a precision improvement.
- **Last-bit rounding of `exp`, `log` and `^`.** Julia's maths library and the C
  runtime gfortran links against round differently now and then. Valid steps agree
  to about 4e-9 relative; after a run's first failed step the legacy model keeps
  integrating from an invalid state (F-08) and the difference grows, up to 9.0e-6
  relative so far. The tests therefore use `rtol = 1e-8` before and `1e-4` after
  the first failure
  (see [Testing](testing.md)).
- **NaN instead of exceptions.** Powers and logarithms of negative numbers give NaN as
  in Fortran (`nanpow`, `nanlog`), never a `DomainError`.
- **`GYM` is never modified in place** (the Fortran supplemental code did, F-09).
  `gym_factor` must be positive: a factor of 0 would make `fE = 0` at the start of the
  gymnosperm–angiosperm ramp, and `fE` divides the mass-balance silicate weathering.
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
  (F-18); in Julia the seed comes only from the configuration. The supplemental
  experiments use the seed of their control (see below), not R's `1234 * 3`.
- **Analysis.** The duplicated `deltaT2Xglac` row and quantiles of placeholder zeros
  (F-17) are not reproduced. Hindcasts reuse saved outputs. Numbers are written to
  `numbers.toml` instead of being printed.

## Decisions of the authors after the code review (2026-11-26)

| finding | decision | implementation |
|:--|:--|:--|
| F-29 | the two Cretaceous stages share a seed | both stages use seed 3702 and the same sampling settings (`experiments/cretaceous/*.toml`), so stage 2 evaluates the same constant draws as stage 1 |
| seed pairing | control and supplemental experiments share a seed | the supplemental experiments use 18510, the seed of the control (main `ct_out50`, `1234 × 15`), and the same sampling settings, so each chunk draws the same constants and forcing series and the comparison is paired; checked in `test/workflow/test_config.jl` |
| F-32 | `f_var_red` was meant to bring the sampled variances in line with the reduced-variance experiments of Royer et al. (2014) | see the known issue below; the code still reproduces R |

## Known issue: `f_var_red` does not change the sampled variances (F-32)

The inverse-Wishart prior on each forcing's covariance uses the scale
`(ν − n_time − 1)·diag(σ²)`, so its mean is `diag(σ²)` for every `ν`, and the variance
of the sampled series is `σ²` whatever `f_var_red` is. `f_var_red` enters only `ν`,
through `ceil(2·max(σ²)/(1 − f))`, which mixes a count with σ² in each forcing's units.
With 20 000 draws per forcing (shipped factors against `f = 0`), the sampled variance is
`σ²` within sampling error (ratio 0.99–1.01) for all 12 forcings. `f` changes only
the tail weight: for example the kurtosis of `d13C` falls from 5.6 to 3.8. For 5 of
the 10 forcings with `f > 0` (`fR`, `fA`, `fD`, `fSR`, `fC`), `ν` is identical with and
without `f`, because `2·max(σ²)/(1 − f)` rounds up to 1 in their units. The R code
behaves the same way, so the published results are reproduced; whether and how to
implement the intended variance reduction is open.

## Not ported (yet)

- Reading the legacy `.RData` outputs (`RData.jl` could be added as a package extension).
- Seven of the seventeen R figures (KDE panels of every parameter, sample-size
  convergence, the supplemental hindcast grid, Cretaceous panels). The numbers behind
  them are available from `src/analysis`.
- The `PR2011` and `LENTON` time-array files and the `PR2011` prior file are not in the
  repository (F-14). The configuration accepts them once they are added to `data/`.
