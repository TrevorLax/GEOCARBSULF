# Changelog

## 0.1.0 (unreleased)

First Julia version, ported from the R/Fortran GEOCARB-precalibration code (porting
decisions D1–D4 in `docs/src/porting_notes.md`):

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

### Continuous integration, documentation and JOSS preparation

- GitHub Actions: test matrix (Linux/macOS/Windows × Julia 1.10/1, 4 threads, pre),
  live comparison with the original R/Fortran code on every push and pull request,
  Documenter build with doctests and deployment, formatting, metadata (CITATION.cff,
  AI usage disclosure), JOSS paper draft, weekly health check, and tag-driven releases
  archived on Zenodo.
- `jldoctest` examples in the docstrings of `run_geocarb`, `ConstantParams` and
  `TimeForcings` and in the manual; a `doctests` test group.
- `AI_USAGE.md` (also the "AI usage" documentation page), `CODE_OF_CONDUCT.md`, issue
  and pull-request templates, `paper/` for JOSS.
- These changes were drafted with an AI coding assistant (see `AI_USAGE.md`).
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

### Git hooks, formatter and stricter CI

- prek git hooks (`.pre-commit-config.yaml`). On commit: whitespace, end-of-file and
  line-ending fixes, YAML/TOML checks, actionlint, zizmor, JuliaFormatter, and a guard
  against changes to `legacy/`. On push: the CHANGELOG/AI-usage check, the golden
  regression tests, the full live comparison with the original R/Fortran code, and the
  documentation build.
- Formatter moved to JuliaFormatter 2.x, pinned exactly (2.14.11) in `tools/format/`,
  which both the hook and the "Formatting" check use.
- `test/tolerances.toml` is now the single source of the tolerances for agreement with
  the Fortran (rtol 1e-8 / 1e-4, atol 1e-10, unchanged), read by the live comparison
  and the golden test.
- New required checks: "Changelog and AI usage" (`Changes.yml`,
  `scripts/ci/check_changes.jl`): every pull request needs a CHANGELOG entry, changes
  to tolerances, fixtures or `legacy/` must be named, AI use must be disclosed and match
  the commit trailers and `AI_USAGE.md`. Dependabot pull requests are exempt.
  "Lint" (`Lint.yml`) runs the commit hooks on all files.
- "Legacy comparison" now runs on a pinned toolchain (`ubuntu-24.04`, R 4.6.1, a dated
  CRAN snapshot) and also checks the golden fixtures against the freshly compiled
  Fortran. `Weekly.yml` runs it with the newest toolchain.
- Documentation deploys without persisted checkout credentials; Dependabot waits 14
  days before proposing a release; batch files are checked out with CRLF.
- These changes were drafted with an AI coding assistant (Claude Code, Claude Opus 5.5;
  see `AI_USAGE.md`).
