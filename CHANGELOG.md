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
- "Changelog and AI usage", "Formatting" and "Lint" run on `ubuntu-latest` (was
  `ubuntu-24.04`), like the other workflows. Lint's ShellCheck now comes from that
  image (0.11 on Ubuntu 26.04, 0.9 on 24.04). "Legacy comparison" stays pinned to
  `ubuntu-24.04` on purpose (fixed gfortran and CRAN binaries; see `Legacy.yml`).
- Documentation deploys without persisted checkout credentials; Dependabot waits 14
  days before proposing a release; batch files are checked out with CRLF.
- These changes were drafted with an AI coding assistant (Claude Code, Claude Opus 5.5;
  see `AI_USAGE.md`).

### Maintenance

- `.git-blame-ignore-revs` no longer lists `d994cb4`. That SHA was the JuliaFormatter
  2.x reformat on the pull-request branch and was never on `main` (the squash merge
  replaced it with `260ba37`, which also holds the CI/CD work and can't be ignored).
  The file now says so, and says how to record future reformat-only commits.
- `CONTRIBUTING.md` and `.pre-commit-config.yaml` give the `SKIP` syntax for cmd and
  PowerShell as well as bash.
- The `trailing-whitespace`, `end-of-file-fixer` and `check-added-large-files` hooks
  run on commit only. The pre-commit-hooks manifest also gave them the pre-push stage.
- `CI_CD_PLAN.md` replaced by the updated plan (state as of 19 November 2026).
- These changes were drafted with an AI coding assistant (Claude Code, Claude Opus 5.5;
  see `AI_USAGE.md`).

### Notebook tour

- **Tolerance unchanged:** `rtol_post` in `test/tolerances.toml` (the tolerance at or
  after a run's first failed step) stays at 1e-4. Tightening it to 1e-6 was tried and
  failed: the golden fixtures regenerated from the Fortran compiled in CI differ by up
  to 9.0e-6 relative there (a temperature in the `supp_gym` variant; the 1000-sample
  live comparison reached 7.6e-7). `test/tolerances.toml` now says so in a comment, and
  the documentation gives these measured values instead of "about 1e-6" and 7.3e-8.
- The golden-master test prints the largest relative difference before and after a
  failed step for each fixture set, variant and quantity, so a tolerance failure shows
  by how much.
- New notebook tour, `notebooks/tour.jl` (Literate.jl source), generating
  `notebooks/GeocarbPrecalibration_tour.ipynb` and the "Notebook tour" documentation
  page. Part 1 introduces the model and package and runs them; Part 2 runs the test
  groups in subprocesses and compares Julia with the original code at three levels
  (golden master; replay of stored R exports in a scratch copy; live R/Fortran run if
  R and a Fortran compiler are found), plotting each check against its tolerance.
  `notebooks/setup.jl` sets it up, `notebooks/build.jl` regenerates it,
  `notebooks/test_notebook.jl` runs it on a scratch copy of the repository, and the new
  `Notebook.yml` workflow runs that on Julia 1.10 and 1.
- `notebooks/build.jl` options: `--execute` (run every cell into the git-ignored
  `notebooks/executed/`), `--hide-home` (replace the home folder with `~` in the
  outputs) and `--html` (one self-contained HTML file via
  `jupyter nbconvert --to html --embed-images`). New workflow `PublishNotebook.yml`:
  at a release tag, with Julia 1.12.5 and the pinned R/gfortran toolchain of
  `Legacy.yml` so that level C runs, it runs the notebook with these three options.
  `Release.yml` now calls it first and creates the release as a draft with the `.ipynb`
  and `.html` attached before publishing it, so the release is complete when it is
  published; a failed notebook run blocks the release. A manual run attaches the files
  to an existing release and refuses to replace files of the same name.
- The "Notebook tour" documentation page now shows outputs and figures. New option
  `notebooks/build.jl --docs-page` runs every cell locally (full mode) into
  `docs/src/generated/notebook_tour.md` with one PNG per figure, replaces the home
  folder with `~`, rewrites the `.ipynb`, and writes `notebook_tour.stamp.toml` with
  hashes of what the page was made from. `docs/src/generated/` is now committed
  (no longer git-ignored) and `docs/make.jl` no longer runs Literate: it checks the
  stamp (`notebooks/tour_stamp.jl`) and fails if `tour.jl` or `tour_helpers.jl` changed
  since the page was made, or if the page was made in quick mode (`--quick`); changes
  to `src/`, `ext/`, `data/`, `experiments/`, `test/` or `Project.toml` only warn. New
  pre-push hook `tour-page-stamp` runs the same check when the tour changes.
- Section 1.12 of the tour no longer calls `display(tbl)`: Literate drops explicit
  `display` calls from executed Markdown, so the quantile table is now the result of
  its own cell and the exceedance note of the next.
- `docs` environment: dependency Literate removed again (the build no longer runs it).
- These changes were drafted with an AI coding assistant (Claude Code, Claude Opus 5.5;
  see `AI_USAGE.md`).
