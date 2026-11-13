# AI usage report

This report says where generative-AI tools were used in GeocarbPrecalibration.jl,
what they were used for, and how their output was checked. It is the source of the
"AI usage" page of the documentation and of the *AI usage disclosure* section of the
JOSS paper (`paper/paper.md`). Keep the three consistent: edit this file, and update
the paper paragraph if the summary changes.

> **TODO (authors):** complete every item marked TODO before submission. Do not
> leave placeholders in a tagged release.

## Summary

<!-- One paragraph; it is mirrored in paper/paper.md. -->
TODO (authors): one-paragraph summary, for example: "Generative-AI coding assistants
(names, versions) were used to help translate the R/Fortran code to Julia, draft
tests and documentation, and set up continuous integration. All AI-assisted code was
reviewed by the authors and is verified against the unmodified original R/Fortran code
(see *Verification*). The authors take full responsibility for the software and the
paper."

## Tools

| tool / model | version or date range | used for |
|:--|:--|:--|
| TODO | TODO | TODO |
| Claude Code (Claude Opus 5.5, Anthropic) | November 2026 | CI/CD workflows, git hooks and check scripts, doctests, JOSS scaffolding (see below) |

## Scope by area

For each area, say whether it is human-written, AI-drafted and then revised by a
person, or mostly AI-generated and reviewed.

| area | files | AI involvement |
|:--|:--|:--|
| model port (`run_geocarb.f90` → Julia) | `src/model/` | TODO |
| inputs, priors, samplers | `src/io/`, `src/priors/`, `src/sampling/` | TODO |
| constraints, engine, analysis | `src/constraints/`, `src/precalibration/`, `src/analysis/` | TODO |
| plotting extension | `ext/`, `src/plotting.jl` | TODO |
| test suite and fixtures | `test/` | TODO |
| legacy-comparison harness | `test/legacy_comparison/` | TODO |
| documentation | `docs/src/`, `README.md` | TODO |
| benchmarks | `benchmark/` | TODO |
| CI/CD, git hooks, doctests, community files, JOSS scaffolding | `.github/`, `.pre-commit-config.yaml`, `scripts/ci/`, `scripts/dev/`, `tools/format/`, `test/tolerances.toml`, jldoctest blocks, `paper/` skeleton, `CODE_OF_CONDUCT.md`, this file's structure | drafted with Claude Code (Claude Opus 5.5) in November 2026; reviewed by the authors. Commits carry a `Co-Authored-By` trailer. |
| paper text | `paper/paper.md` | TODO |

The original R and Fortran code in `legacy/` was written by its authors before this
project and is not AI-generated. It is kept unmodified.

## Verification

AI-assisted code is held to the same checks as any other code. Continuous
integration runs all of them on every push and pull request:

1. **Live comparison with the original code** (`test/legacy_comparison/`). The
   unmodified R/Fortran code is run on 1000 prior samples and six supplemental
   variants. Julia must reproduce CO2, O2 and temperature at every step within
   `rtol = 1e-8`, or `1e-4` after a run's first failed step. The positions of failed
   steps must be identical, and % outbound must be equal.
2. **Golden-master fixtures** from the compiled Fortran (`test/regression/`), checked
   on Linux, macOS and Windows.
3. **Unit, statistical, workflow and quality tests** (Aqua.jl), and **doctests** of
   every documented example.
4. **Human review.** TODO (authors): describe your review process, for example
   line-by-line comparison with the Fortran, and the porting findings F-01 to F-xx
   recorded in `docs/src/porting_notes.md`.

## Responsibility

The authors have reviewed all AI-assisted code, documentation and text, understand
it, and take full responsibility for its correctness and for the content of the
paper. No AI tool is listed as an author.

## Contributions

Contributors must say in their pull request whether and how AI tools were used (see
`CONTRIBUTING.md`). The pull-request template asks for it. Significant AI-assisted
changes are noted in `CHANGELOG.md`.
