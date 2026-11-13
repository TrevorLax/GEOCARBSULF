# GeocarbPrecalibration.jl

A Julia implementation of the **GEOCARBSULFvolc** long-term carbon-cycle model and of
the **precalibration** workflow used by Wong et al. (2021), *A tighter constraint on
Earth-system sensitivity from long-term temperature and carbon-cycle observations*.
It is a port of the R/Fortran code `GEOCARB-precalibration` by Tony Wong and Ying Cui.

## Statement of need

GEOCARB-type models are the standard tool for reconstructing Phanerozoic CO2 and
for constraining Earth-system sensitivity from the geological record. The original
precalibration code mixes R driver scripts with a compiled Fortran model, edits
experiment settings in place, and is difficult to extend, test or run in parallel.
GeocarbPrecalibration.jl gives the same model and workflow as one documented, tested
Julia package. It reproduces the compiled Fortran to rounding error, which is checked
continuously against the original code. Runs are deterministic across thread counts,
experiments are declared in TOML files, and model variants are options rather than
copies of the source.

## Quick start

```jldoctest quickstart
julia> using GeocarbPrecalibration

julia> table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"));

julia> arrays = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"));

julia> p = mean_constants(table);   # the 56 constants at their prior means

julia> f = arrays.center;           # the 12 forcings at their central estimates

julia> r = run_geocarb(p, f);       # 570 Ma → present, 10 Myr steps

julia> succeeded(r)                 # every step converged
true

julia> round(r.co2[end]; digits = 1)            # present-day CO2, ppmv (Inf on failed steps)
243.7

julia> round(temperature(r)[end]; digits = 2)   # °C, comparable with the Mills et al. (2019) windows
14.78
```

Run a (small) precalibration experiment from a configuration file. This takes about a
minute, so it is not run as a doctest:

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
