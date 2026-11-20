# Testing

```text
julia --project=. -e "using Pkg; Pkg.test()"                          # everything except the R comparison
GROUP=unit julia --project=. -e "using Pkg; Pkg.test()"               # one group
julia --project=. test/legacy_comparison/run_comparison.jl            # compare with the original R/Fortran
```

| group | what |
|:--|:--|
| `unit` | physics pieces (climate, vegetation, fluxes, solver), step-status invariants on 200 prior draws, supplemental options, input validation, zero allocations, Float32 and ForwardDiff inputs |
| `io` | CSV reader (BOM, CRLF, CR-only, quotes), prior table, time arrays, proxies, temperature data |
| `sampling` | Latin hypercube strata, truncated priors (KS tests), inverse-Wishart degrees of freedom, sampler moments, IW ≡ multivariate-t |
| `constraints` | CO2 and temperature windows, % outbound semantics |
| `workflow` | configuration files, engine (stopping rule, single chunk, determinism across thread counts, checkpoint/resume), save/load, analysis |
| `regression` | golden master against fixtures from the compiled Fortran (when generated; see `test/fixtures/README.md`) |
| `quality` | Aqua.jl (stale dependencies, compat bounds, piracy, ambiguities) |
| `doctests` | the `jldoctest` examples in docstrings (the manual's doctests run in `docs/make.jl`) |
| `legacy` | end-to-end comparison with the original R/Fortran code; needs R (see `test/legacy_comparison/README.md`) |

The legacy comparison runs the unmodified R code on 1000 samples and feeds exactly
those samples to Julia, using the default `fortran_single_literals = true`. The
`regression` golden test does the same on 100 of those samples stored in
`test/fixtures/fortran/`, so it runs without R.

## Tolerances

Both tests judge every run in two regions, split at the run's **first failed step**
(the first `Inf` in the legacy CO2):

| check | requirement |
|:--|:--|
| `Inf`/`NaN` positions | identical (the same steps fail) |
| % outbound | identical |
| values before the first failed step | `abs(a − b) ≤ 1e-10 + 1e-8·max(abs(a), abs(b))` |
| values at or after the first failed step | `abs(a − b) ≤ 1e-10 + 1e-6·max(abs(a), abs(b))` |

Why two regions: Julia's `exp`, `log` and `^` and the C runtime used by gfortran
occasionally round the last bit differently. Two builds of the *same* Fortran (the
main and supplemental libraries) already differ by up to 8e-10 for that reason. In a
valid step the model is well conditioned and the difference stays below about 4e-9.
After a failed step the legacy code keeps integrating from an invalid state (finding
F-08), the next steps are badly conditioned, and the same last-bit difference grows:
in the 1000-sample comparison of 30 October 2026 the largest *relative* difference
there was 7.3e-8 (the largest *absolute* difference, 1.3e-6 in a temperature, is
where the figure of "about 1e-6" in earlier versions of this page came from). The
tolerance after a failure was 1e-4 until November 2026 and is now 1e-6, about 14
times the largest difference seen. A real porting error is still caught: it changes
valid steps far more than 1e-8, or moves a failure, or changes a % outbound.

The report (`test/legacy_comparison/output/comparison_report.txt`) lists the worst
cells of each region with their run, age, step status, solver iterations and the
age of the run's first failure. The tolerances are kept in `test/tolerances.toml`, which
the golden-master test reads too; CI never overrides them, and a change to the file
needs a CHANGELOG entry that says so. For experiments they can be overridden with
`--rtol-clean`, `--rtol-post` and `--atol`. With CairoMakie installed, the run also draws
figures of these differences into `test/legacy_comparison/output/figures/` (see
`test/legacy_comparison/README.md`).

The comparison also reports, for information only, how far Julia with
`fortran_single_literals = false` is from the legacy output (pass/fail flips and
relative differences).

## The notebook tour

`notebooks/tour.jl` (also the "Notebook tour" page) runs the test groups one by one,
repeats the golden-master comparison with its statistics kept, replays stored R exports
if `test/legacy_comparison/output` has any, and runs the live comparison if R and a
Fortran compiler are found. For every check it plots the largest relative difference
against its tolerance. `notebooks/test_notebook.jl` runs the whole notebook on a scratch
copy of the repository; the `Notebook.yml` workflow runs it on Julia 1.10 and the newest
release.

## Continuous integration

Before code reaches GitHub, the prek hooks in `.pre-commit-config.yaml` (see
`CONTRIBUTING.md`) format it, and on every `git push` run the CHANGELOG/AI-usage check,
the golden test and the full live comparison with the R/Fortran code.

GitHub Actions (`.github/workflows/`) runs on every push and pull request:

| workflow | check name | what |
|:--|:--|:--|
| `CI.yml` | CI result | `Pkg.test()` on Linux, macOS and Windows × Julia 1.10 (LTS) and 1, plus 4 threads and the pre-release (allowed to fail); coverage to Codecov. Includes the `regression` golden test, so every platform is checked against the Fortran output |
| `Legacy.yml` | Legacy comparison | on a pinned toolchain (`ubuntu-24.04`, R 4.6.1, dated CRAN snapshot): builds the original Fortran with gfortran, runs the unmodified R code and `run_comparison.jl`, then regenerates the golden fixtures from that Fortran and runs the golden test on them; report in the job summary, all output as an artifact |
| `Docs.yml` | Documentation | docstring doctests, then `docs/make.jl` (manual doctests, strict cross-references), deployed to GitHub Pages from `main` (dev), tags (stable) and pull requests (previews) |
| `Format.yml` | Formatting | BlueStyle, with the JuliaFormatter 2.x pinned in `tools/format` (the same as the pre-commit hook) |
| `Changes.yml` | Changelog and AI usage | pull requests: CHANGELOG entry, AI disclosure and trailers, special changes named (`scripts/ci/check_changes.jl`) |
| `Lint.yml` | Lint | the pre-commit hooks on all files: file hygiene, actionlint, zizmor |
| `Metadata.yml` | Metadata | `CITATION.cff` validity, presence of the AI usage disclosure, matching versions |
| `Paper.yml` | | JOSS paper PDF (when `paper/` changes) |
| `PublishNotebook.yml` | | called by `Release.yml`: runs the notebook tour in full at the release tag (Julia 1.12.5, with R and gfortran, so level C runs) and produces the executed `.ipynb` and a self-contained `.html`; manual runs attach them to an existing release, never replacing files already there |
| `Notebook.yml` | | the notebook tour in quick mode on Julia 1.10 and 1, and that the committed `.ipynb` matches `notebooks/tour.jl` (when the notebook, sources or tests change; not required) |
| `Weekly.yml` | | Mondays: tests with the newest dependencies, legacy comparison with the newest R/CRAN/runner, documentation link check, JET |
| `Release.yml` | | tag `vX.Y.Z`: checks versions, CHANGELOG and placeholders, runs `PublishNotebook.yml`, then creates the GitHub release as a draft with the notebook attached and publishes it (archived by Zenodo) |

Branch protection on `main` should require *CI result*, *Legacy comparison*,
*Documentation*, *Formatting*, *Metadata*, *Changelog and AI usage* and *Lint*.

### Retiring the comparison with the R/Fortran code

The live comparison is meant to be temporary. To drop it:

1. delete `.github/workflows/Legacy.yml`, the `legacy` job in `Weekly.yml` and the
   `legacy-comparison` hook in `.pre-commit-config.yaml`;
2. remove *Legacy comparison* from the required checks of `main`;
3. keep `test/regression`, `test/fixtures/fortran/` and `test/tolerances.toml`. They keep pinning the model to
   the original Fortran output on every platform, without R. `legacy/` and
   `test/legacy_comparison/` can stay so the comparison can still be run by hand.
