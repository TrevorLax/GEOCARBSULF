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
| values at or after the first failed step | `abs(a − b) ≤ 1e-10 + 1e-4·max(abs(a), abs(b))` |

Why two regions: Julia's `exp`, `log` and `^` and the C runtime used by gfortran
occasionally round the last bit differently. Two builds of the *same* Fortran (the
main and supplemental libraries) already differ by up to 8e-10 for that reason. In a
valid step the model is well conditioned and the difference stays below about 4e-9.
After a failed step the legacy code keeps integrating from an invalid state (finding
F-08), the next steps are badly conditioned, and the same last-bit difference grows
to about 1e-6. A real porting error is still caught: it changes valid steps far more
than 1e-8, or moves a failure, or changes a % outbound.

The report (`test/legacy_comparison/output/comparison_report.txt`) lists the worst
cells of each region with their run, age, step status, solver iterations and the
age of the run's first failure. Tolerances can be changed with `--rtol-clean`,
`--rtol-post` and `--atol`. With CairoMakie installed, the run also draws
figures of these differences into `test/legacy_comparison/output/figures/` (see
`test/legacy_comparison/README.md`).

The comparison also reports, for information only, how far Julia with
`fortran_single_literals = false` is from the legacy output (pass/fail flips and
relative differences).
