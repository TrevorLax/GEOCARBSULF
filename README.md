# GeocarbPrecalibration.jl

A Julia implementation of the **GEOCARBSULFvolc** long-term carbon-cycle model and the
Latin-hypercube **precalibration** of Wong et al. (2021), *A tighter constraint on
Earth-system sensitivity from long-term temperature and carbon-cycle observations*
(Nature Communications 12, 3173). It is a port of the R/Fortran code
`GEOCARB-precalibration` by Tony Wong and Ying Cui. The original code is kept,
unmodified, in [`legacy/`](legacy/README.md).

- **Faithful.** The model is a line-by-line port of `run_geocarb.f90`.
  `test/legacy_comparison` runs the original R/Fortran code and checks that Julia
  reproduces it to rounding error.
- **Readable.** Parameters are referred to by name, the model is split into small
  documented functions, and experiments are TOML files.
- **Robust.** Inputs are validated with clear errors. Numerical failures are reported
  per time step and never crash an ensemble. Runs are deterministic regardless of the
  number of threads, and long runs can be checkpointed.
- **Tested.** Unit, input/output, statistical, workflow, golden-master and
  legacy-comparison tests; see [Testing](docs/src/testing.md).

## Installation

Requires Julia ≥ 1.10.

```text
cd GEOCARD_juliaed
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## Ten-line example

```julia
using GeocarbPrecalibration

table  = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
arrays = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
r = run_geocarb(mean_constants(table), arrays.center)   # 570 Ma → present
r.co2, temperature(r)

res = run_precalibration(only(load_experiments("experiments/example_small.toml")))
climate_sensitivity_summary(res)
```

## Reproducing the paper

```text
julia --project=. -t auto scripts/run_experiment.jl experiments/main/grid.toml
julia --project=. -t auto scripts/run_experiment.jl experiments/main/ct_out30_extra_seeds.toml
julia --project=. -t auto scripts/run_experiment.jl experiments/supplemental/gym.toml        # and the other four
julia --project=. -t auto scripts/run_experiment.jl experiments/cretaceous/stage1.toml
julia --project=. -t auto scripts/run_experiment.jl experiments/cretaceous/stage2.toml
julia --project=. scripts/analysis_main.jl            # numbers.toml, tables, figures (with CairoMakie)
julia --project=. scripts/analysis_supplemental.jl
julia --project=. scripts/analysis_cretaceous.jl
```

Use `--dry-run` to validate a configuration quickly and `--checkpoint` for long runs.
For figures, install CairoMakie once (`julia -e "using Pkg; Pkg.add(\"CairoMakie\")"`);
the plotting extension then loads automatically.

## Tests

On Windows, double-click `run_tests.bat` (or run it from a terminal). It installs the
dependencies, runs the comparison with the original R/Fortran code and the test suite,
and writes `logs/*.log`. Or run the steps directly:

```text
julia --project=. -e "using Pkg; Pkg.test()"                     # full suite (a few minutes)
julia --project=. test/legacy_comparison/run_comparison.jl       # vs the original R/Fortran (needs R)
```

## Layout

```text
src/            model, inputs, priors, samplers, constraints, engine, analysis
ext/            plotting (Makie extension)
data/           input data (copied from the original input_data/) and variance_reduction.toml
experiments/    experiment configurations (main, supplemental, Cretaceous, example)
scripts/        command-line entry points
test/           test suite; test/legacy_comparison compares with the original code
docs/           Documenter.jl documentation
legacy/         the original R and Fortran code, unmodified
ci/             GitHub Actions workflows (move to .github/workflows to enable)
```

## Documentation

Build with `julia --project=docs docs/make.jl` (after `Pkg.develop(path=".")` in the
docs environment). Start with [the model](docs/src/model.md),
[precalibration](docs/src/precalibration.md), [experiments](docs/src/experiments.md)
and the [porting notes](docs/src/porting_notes.md).

## Licence and credit

GNU General Public License v3 or later (see `LICENSE`), as the original.
GEOCARB-precalibration © 2021 Tony Wong; model code by Ying Cui and Tony Wong, after
the GEOCARBSULFvolc model of R. A. Berner and the FORTRAN implementation of Park &
Royer (2011). Please cite Wong et al. (2021) and this software (`CITATION.cff`).
