# Contributing

Contributions, bug reports and questions are welcome. Everyone taking part is expected
to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs and requesting features

Open an [issue](../../issues/new/choose) using the bug-report or feature-request form.
For a bug, include a minimal example, the full error message, and the output of
`versioninfo()` and `Pkg.status()`. If you suspect a numerical difference from the
original R/Fortran code, say whether `test/legacy_comparison/run_comparison.jl` passes.

## Getting help

Ask usage questions in GitHub Discussions, or open an issue. The documentation
(model, precalibration, experiments, API) is the first place to look.

## Pull requests

1. Fork, create a branch, and install the git hooks once (see *Git hooks* below).
2. Make your change with tests, and add an entry to the top, unreleased section of
   `CHANGELOG.md`. Every change needs one; there is no label to skip it.
3. Run the test suite. The pre-push hook runs the golden test and the live comparison
   with the original R/Fortran code on every push; run them by hand if you skip the
   hooks.
4. Build the documentation (`julia --project=docs docs/make.jl`). This also runs every
   `jldoctest`. After an intended change of output, regenerate the expected output
   with `doctest(GeocarbPrecalibration; fix = true)` (see the header of `docs/make.jl`)
   and review the diff.
5. Open the pull request and fill in the template, including exactly one of the two AI
   boxes. CI must be green. The required checks are "CI result", "Legacy comparison",
   "Documentation", "Formatting", "Metadata", "Changelog and AI usage" and "Lint".

## Git hooks

The hooks in `.pre-commit-config.yaml` run with [prek](https://github.com/j178/prek)
(`pre-commit` reads the same file). Install prek (for example `uv tool install prek`,
`pipx install prek` or the standalone installer), then, once per clone:

```text
prek install                               # pre-commit and pre-push hooks
SKIP=legacy-untouched prek run --all-files # first run over everything
```

- **On commit:** whitespace, end-of-file and line-ending fixes, YAML/TOML checks,
  actionlint and zizmor on the workflows, JuliaFormatter, and a guard that refuses
  changes to `legacy/`.
- **On push:** `scripts/ci/check_changes.jl` (CHANGELOG entry and AI usage, the same
  check as the "Changelog and AI usage" CI job), the `regression` test group, the full
  live comparison with the original R/Fortran code (needs R; see
  `test/legacy_comparison/README.md`), and the documentation build when docs or
  docstrings may have changed.

The formatter is JuliaFormatter 2.x, pinned exactly in `tools/format/Project.toml`; the
hook and the "Formatting" CI check use that environment, so they always agree. To
format everything by hand: `prek run juliaformatter --all-files`.

Hooks can be skipped (`git commit --no-verify`, `SKIP=hook-id`), but CI runs the same
checks and `main` requires them.

## AI-assisted contributions

You may use generative-AI tools, but you must:

- say in the pull request which tools you used and for what (the template asks);
- understand, review and test every AI-assisted change yourself, because you are
  responsible for it;
- not submit AI output you could not explain in review.

AI-assisted changes say so in their `CHANGELOG.md` entry, and the project-level report
is kept in [`AI_USAGE.md`](AI_USAGE.md). CI checks that:

- exactly one AI box of the pull-request template is ticked;
- every AI tool named in a commit's `Co-Authored-By` trailer is listed in the *Tools*
  table of `AI_USAGE.md`, and the CHANGELOG entry mentions AI;
- if the *Summary* of `AI_USAGE.md` changes, the paper's *AI usage disclosure* changes
  too.

Pull requests opened by Dependabot are exempt from the CHANGELOG and disclosure rules.

## Code guidelines

- **Style**: [BlueStyle](https://github.com/JuliaDiff/BlueStyle) (`.JuliaFormatter.toml`).
  Keep the physics variable names of Berner / the Fortran (`Fwsi_0`, `dlsy`, …) so the
  code can be traced to the literature, and document each one.
- **Tests**: every change needs a test. Run `julia --project=. -e "using Pkg; Pkg.test()"`.
  The pre-push hook runs `test/legacy_comparison/run_comparison.jl` on every push.
- **Tolerances and fixtures**: the agreement with the Fortran is judged with
  `test/tolerances.toml`. Changing it, the golden fixtures in `test/fixtures/fortran/` or
  anything in `legacy/` needs a CHANGELOG entry that names it ("tolerance", "fixture",
  "legacy/") and explains why; CI enforces this.
- **Do not "simplify" the model expressions** in `src/model/co2_solver.jl` and
  friends. They follow the Fortran's order of operations so that results agree to
  rounding error.

## Adding a constant parameter or forcing

1. add the name to `CONSTANT_PARAMETER_NAMES` (or `TIME_FORCING_NAMES`) and its
   description and units to `PARAMETER_INFO` in `src/parameters/names.jl`;
2. add the field to `ConstantParams` (or `TimeForcings`);
3. add the row (or columns) to the input CSV in `data/`;
4. use it in `src/model/`, and add a unit test and a note in `docs/src/porting_notes.md`.

## Adding a model variant

Add a `ModelOptions` field whose default keeps today's behaviour, implement it,
validate it in `validate(::ModelOptions)`, and test both the default (the legacy
comparison must still pass) and the new behaviour.

## Regenerating fixtures

See `test/fixtures/README.md` and `test/legacy_comparison/README.md`.
