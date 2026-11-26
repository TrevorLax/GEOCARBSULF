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

### Fixes from the code review of 2026-11-25 (findings J-01 to J-32)

Drafted with an AI coding assistant (Claude Code; see `AI_USAGE.md`) and checked by the
full test suite, the golden-master fixtures and bit-for-bit comparisons of model and
engine outputs with the previous code. Results with the default options are unchanged.

**Breaking:**

- The exported names `update`, `temperature` and `validate` are now `update_params`,
  `surface_temperature`, `validate_config` (experiment configurations) and
  `validate_options` (`ModelOptions`). The old names work qualified
  (`GeocarbPrecalibration.update`) with a deprecation warning (J-32).
- `ModelOptions` requires `gym_factor > 0` (0 made every run fail at 130 Ma) and
  `iteration_threshold ≥ 2` (J-12, J-26).
- Checkpoint directories carry `checkpoint_manifest.toml`; directories written by
  earlier versions are refused instead of reused (J-03).
- `time_center_from` refuses a result run with `run_on_time_centers = true` unless
  `allow_uninformative_centers = true`; `experiments/cretaceous/stage2.toml` sets it to
  keep the R-parity run (J-11).
- `run_experiment.jl` refuses to overwrite existing results without `--force` (J-04).
- Age grids must run from 570 Ma to the present (J-20); windows and proxy rows must not
  be inverted (J-24); experiment tags must be unique and unshipped `fsr_choice` /
  `param_choice` files are reported at load time (J-28).

**Results and their presentation:**

- Checkpoints are tied to the configuration and input files that wrote them (inputs
  compared by content, so a moved project can resume) and are written atomically
  (J-03); a failed chunk write leaves no temporary file. In threaded runs, an error
  inside a chunk is rethrown as itself instead of as a `TaskFailedException`, and
  Ctrl-C still stops the run.
- `plot_model_vs_proxy` plots `temp + T0`, the quantity acceptance tested, instead of
  `temp + T0 + GEOG`; new `accepted_temperature` (J-13). `hindcast` no longer mixes
  centre-run outputs with sampled GEOG for `run_on_time_centers` results (J-02), and
  rejects `center` for other results, where it would be ignored.
- New `n_evaluated` and `acceptance_rate`: `n_simulated` counted the rest of the last
  chunk and biased acceptance rates low (J-17).
- `correlation_screen` lists undefined (NaN) correlations last (J-18).
- The Cretaceous analysis merges all three 30 % control seeds and adds a 50 % control
  (J-01); the analysis scripts read inputs, `nsig` and `T0` from each result's stored
  configuration through the new `result_inputs` (J-14). For a result copied from
  another machine, `result_inputs` looks up missing input files by name in the
  package data directory, with a warning.

**Configuration and provenance:**

- Stored configurations round-trip losslessly (`nothing` omitted, native TOML `inf`);
  `ExperimentConfig(res.config)` rebuilds an experiment; `with_overrides` records the
  overridden fields; unreadable stored configurations raise an error (J-16).
- Results record the active project, the manifest SHA-256 and dependency versions
  (`environment_provenance`); `reproduce/` holds the pinned-environment instructions
  (its `Manifest.toml` is still to be created on the paper machine) (J-05).
- New dependency: the SHA standard library.

**Decisions of the authors (2026-11-26):**

- The supplemental experiments now use seed 18510, the seed of their control (main
  `ct_out50`), with the same sampling settings, so each chunk draws the same constants
  and forcing series and the comparison is paired (previously 3702, from R). A test
  checks the pairing.
- The two Cretaceous stages share a seed (F-29), as before; now documented and tested.
- `f_var_red` (F-32): its intent (variances in line with Royer et al. 2014) is
  documented, together with the finding that it does not change the sampled variances,
  in R or here; see `docs/src/porting_notes.md`.

**Model options (off by default, Fortran behaviour unchanged):** `report_nan_target`
(J-21) and `unified_vascular_blend` (J-22).

**Other fixes:** shared `DEFAULT_MODEL_OPTIONS` can no longer be mutated, `isequal`
agrees with `hash` (J-19); `fortran_single_literals` rounds only options left at their
Fortran defaults (J-07); tolerant `dt` check (J-06); `run_geocarb!` checks the output's
age grid (J-25); `TruncatedPrior` rejects zero-mass truncations and handles far upper
tails (J-23); CSV errors cite exact file lines and Float32 values round-trip (J-27);
supported number types documented, dual-number derivatives tested against finite
differences (J-08).

**Documentation and maintenance:** the solar-luminosity term is described consistently
(`r.temp` includes it; `remove_solar` keyword) (J-15); documentation drift fixed (J-09);
legacy file and line references moved from docstrings to a table in
`docs/src/porting_notes.md` (J-29); one Newton loop in `solve_rco2`, bit-for-bit
identical (J-30); sampler workspaces and preallocated assembly make the engine about
19 % faster per sample with identical results (J-31); one proxy-binning helper with an
explicit `dt` (J-32). J-10 needed no change.

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
- `docs` environment: new dependency Literate.
- These changes were drafted with an AI coding assistant (Claude Code, Claude Opus 5.5;
  see `AI_USAGE.md`).
