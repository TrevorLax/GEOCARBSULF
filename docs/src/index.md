# GeocarbPrecalibration.jl

A Julia implementation of the **GEOCARBSULFvolc** long-term carbon-cycle model and of
the **precalibration** workflow used by Wong et al. (2021), *A tighter constraint on
Earth-system sensitivity from long-term temperature and carbon-cycle observations*.
It is a port of the R/Fortran code `GEOCARB-precalibration` by Tony Wong and Ying Cui.

## Quick start

```julia
using GeocarbPrecalibration

table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
arrays = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))

p = mean_constants(table)          # the 56 constants at their prior means
f = arrays.center                  # the 12 forcings at their central estimates
r = run_geocarb(p, f)              # 570 Ma → present, 10 Myr steps

r.co2                              # ppmv; Inf on failed steps
temperature(r)                     # °C, comparable with the Mills et al. (2019) windows
```

Run a (small) precalibration experiment from a configuration file:

```julia
cfgs = load_experiments("experiments/example_small.toml")
res = run_precalibration(only(cfgs))
climate_sensitivity_summary(res)
```

or from the command line, using all CPU threads:

```text
julia --project=. -t auto scripts/run_experiment.jl experiments/main/grid.toml --only tag=ct_out30
```

## Reproducing the paper

| step | R (original) | Julia |
|:--|:--|:--|
| main experiments | `source("lhs_driver.R")` | `scripts/run_experiment.jl experiments/main/grid.toml` and `…/ct_out30_extra_seeds.toml` |
| supplemental experiments | `source("lhs_driver_supp.R")` | `scripts/run_experiment.jl experiments/supplemental/<name>.toml` |
| Cretaceous experiment | `lhs_driver_cret.R`, edit, `cretaceous_experiment.R`, edit, rerun | `experiments/cretaceous/stage1.toml`, then `stage2.toml` |
| analysis and figures | `analysis_and_plots.R` | `scripts/analysis_main.jl`, `analysis_supplemental.jl`, `analysis_cretaceous.jl` (figures with CairoMakie) |

The random number generators of R and Julia differ, so individual samples differ; the
model itself reproduces the compiled Fortran to rounding error (see [Testing](@ref)).

## How to cite

Please cite Wong et al. (2021) and this software (see `CITATION.cff`). The code is
licensed under the GNU General Public License v3 or later, like the original.
