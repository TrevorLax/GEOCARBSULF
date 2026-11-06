# Changelog

## 0.1.0 (unreleased)

First Julia version, ported from the R/Fortran GEOCARB-precalibration code following
`JULIA_REWRITE_PLAN.md` with the proposed defaults of its §9:

- GEOCARBSULFvolc model (`run_geocarb`), including the supplemental variants as `ModelOptions`;
- input readers, truncated priors, Latin hypercube and inverse-Wishart / multivariate-t samplers;
- CO2 and temperature windows, % outbound, composable acceptance rules;
- chunked, threaded, deterministic, checkpointable precalibration engine; JLD2 results;
- TOML experiment configurations for every experiment of the original code;
- analysis functions and a Makie plotting extension;
- test suite, including an end-to-end comparison with the original R/Fortran code.

Known differences from the R/Fortran code are listed in `docs/src/porting_notes.md`.

### Changes after the first test run

- `ModelOptions(fortran_single_literals = true)` is now the **default**: version 1
  reproduces the single-precision literals of the compiled Fortran (finding F-05).
  `false` remains available and is documented as a model change.
- Legacy comparison and golden test judge each run before and after its first failed
  step separately (`rtol` 1e-8 and 1e-4), with identical `Inf`/`NaN` positions and %
  outbound. The 1e-9 tolerance failed on last-bit library rounding amplified after
  failed steps. The report lists the worst cells with their step status.
- Golden-master fixtures from the original R/Fortran (100 samples, main and six
  supplemental variants) in `test/fixtures/fortran/`, so the `regression` group runs
  without R.
- Fixed `tmpfile` in the test helpers for `SubString` input (the one test error).
- Tests for `reject_failed_runs` and the Cretaceous window rule that actually accept
  and reject runs (the earlier 20-sample smoke tests accepted none).
- `run_tests.bat` writes time-stamped log files, so sync clients no longer create
  "name clash" copies.

### Timing benchmark

- New `benchmark/timing` harness and `run_timing.bat`, implementing
  `TIMING_BENCHMARK_PLAN.md`: R/Fortran and Julia timed component by component in fresh,
  interleaved processes, with correctness guards, drift sentinels, a memory guard and a
  generated report. Results go outside the synced folder
  (`%LOCALAPPDATA%\GeocarbTiming`). See `benchmark/timing/README.md` and the new
  "Performance" documentation page.
- New dependency **TimerOutputs** (decision T3): `run_precalibration` has
  `@timeit_debug` sections, compiled out unless switched on. Results are unchanged
  with the sections on (checked by the benchmark).

