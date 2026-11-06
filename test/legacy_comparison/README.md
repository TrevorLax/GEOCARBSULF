# Comparison with the original R/Fortran code

This test runs the **unmodified** R and Fortran code (in `legacy/`) on a small sample
and checks that the Julia port gives the same numbers, to within floating-point
rounding.

```text
julia --project=. test/legacy_comparison/run_comparison.jl
```

or, as part of the test suite,

```text
julia --project=. -e "using Pkg; Pkg.test(test_args = [\"legacy\"])"
```

## Requirements

- **R** (tested with R ≥ 4.1). The script finds `Rscript` on the `PATH`, in
  `C:\Program Files\R\R-*\bin`, or wherever the `RSCRIPT` environment variable
  points.
- The R packages `lhs`, `CholWishart`, `abind` and `MASS`. Missing ones are installed
  into your user library from CRAN on the first run.
- The compiled Fortran. `legacy/fortran/run_geocarb.dll` (Windows) or `.so` is used if
  present. Otherwise both libraries are compiled with `R CMD SHLIB`, which needs a
  Fortran compiler (on Windows, Rtools). By hand:
  `gfortran -shared -fPIC -fno-range-check -o run_geocarb_supp.dll src/run_geocarb_supp.f90`
  in `legacy/fortran`.

## What is compared

`run_legacy.R` calls the original `lhs.R` with `prcout_threshold = 1`, so every
simulation is kept (1000 by default, drawn with the original LHS, inverse-Wishart
and `mvrnorm` sampling). It exports all inputs and outputs with 17 significant
digits. `compare.jl` then runs the Julia code on **exactly those inputs** and checks:

1. time-array centres and σ, inverse-Wishart degrees of freedom, CO2 and temperature
   windows;
2. the truncated-prior quantile transform;
3. CO2, O2 and temperature at every time step of every sample, including the
   positions of failed (`Inf`) and `NaN` steps;
4. % outbound;
5. the run at the prior means;
6. the six supplemental-experiment settings of `run_geocarb_supp.f90`;
7. if the Fortran library can be loaded from Julia, a direct `ccall` check.

`Inf`/`NaN` must be in exactly the same places and % outbound must be identical.
Finite values must satisfy `|a − b| ≤ atol + rtol·max(|a|, |b|)` with `atol = 1e-10`
and

- `rtol = 1e-8` **before** a run's first failed step,
- `rtol = 1e-4` **at or after** it.

Julia's `exp`/`log`/`^` and the C runtime used by gfortran sometimes round the last
bit differently. That stays below about 4e-9 in valid steps, but the legacy model
keeps integrating after a failed step (finding F-08), which amplifies it to about
1e-6. `docs/src/testing.md` explains this in detail. The random numbers themselves
are not compared: R and Julia use different generators, which is why the Julia code
is fed R's samples.

The original Fortran stores decimal literals such as `0.01`, `0.7` and `log(2.0)`
in single precision (finding F-05). Julia reproduces this by default
(`ModelOptions(fortran_single_literals = true)`), and the comparison uses it. For
information, the report also says how far Float64 literals
(`fortran_single_literals = false`) would be from the legacy output.

Options of `run_comparison.jl`: `--legacy-dir`, `--out`, `--n`, `--n-supp`, `--seed`,
`--rtol-clean`, `--rtol-post`, `--atol`, `--worst N` (worst cells listed per region),
`--skip-r` (reuse the R exports), `--rscript`. See the header of the script.

The report is written to `test/legacy_comparison/output/comparison_report.txt`.
The Julia outputs are saved next to the R exports (`output/julia/`), and the
statistics of every check go to `output/comparison_stats.csv`.

## Figures

If [CairoMakie](https://docs.makie.org) can be loaded, `run_comparison.jl` finishes by
drawing figures into `test/legacy_comparison/output/figures/` (skip them with
`--no-plots`). CairoMakie is not a dependency of the package; install it once in your
default environment with `julia -e "using Pkg; Pkg.add(\"CairoMakie\")"`. To redraw
the figures from an earlier run without running anything else:

```text
julia --project=. test/legacy_comparison/plot_comparison.jl [output folder]
```

| figure | shows |
|:--|:--|
| `01_check_overview.png` | every value check: largest relative difference next to its tolerance, pass/fail |
| `02_centre_run.png` | the run at the prior means: legacy and Julia CO2, O2 and temperature, and their relative difference at each age |
| `03_ensemble.png` | quantile bands of CO2 and temperature over all samples (legacy filled, Julia as lines), and the share of valid steps at each age |
| `04_one_to_one.png` | Julia against legacy for every finite cell, coloured by region |
| `05_reldiff_histograms.png` | distribution of the relative differences before and at/after a run's first failed step, with both tolerances |
| `06_reldiff_heatmaps.png` | relative difference for every run and age; failed steps grey, first failure marked |
| `07_reldiff_by_age.png` | largest and median relative difference at each age, per region |
| `08_percent_outbound.png` | % outbound (the acceptance criterion), Julia against legacy |
| `09_literals.png` | CO2 differences with single- vs double-precision literals (finding F-05) |

Relative differences are `|a − b| / max(|a|, |b|)` as in the checks; exactly equal
values are drawn at 10⁻¹⁸ and labelled 0.
