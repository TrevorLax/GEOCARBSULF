# Experiments

Experiments are TOML files in `experiments/`; [`load_experiments`](@ref) turns a file
into one or more [`ExperimentConfig`](@ref)s.

```toml
name         = "main"
param_choice = "all"        # → GEOCARB_input_summaries_calib_all.csv
data_choice  = "F2017"      # Foster et al. (2017) CO2 proxies
fsr_choice   = "DT2019"     # → GEOCARB_input_arrays_NewDegassing.csv
n_sample     = 20_000_000   # at most this many simulations
n_per_chunk  = 10_000
n_accept_min = 10_000       # stop once this many are accepted
output_dir   = "results/main"

[grid]                      # one experiment per (constraint, threshold)
constraint      = ["co2", "temp", "both"]
threshold       = [0.30, 0.35, 0.40, 0.45, 0.50]
seed_multiplier = 1234      # seed = 1234 × experiment index, as in lhs_driver.R

[model]                     # ModelOptions; empty = run_geocarb.f90
```

Other keys: `constraint`, `threshold` and `seed` (single experiment), `tag_suffix`,
`reject_failed_runs`, `cretaceous_age`, `run_on_time_centers`, `time_center_from`,
`constant_design`, `time_sampler`, `save_covariances`, `nsig`, `T0`, explicit file
names (`prior_file`, `time_array_file`, `proxy_file`, `temperature_file`,
`variance_reduction_file`) and `data_dir`. Unknown keys are errors, so typos are caught.

Run with

```text
julia --project=. -t auto scripts/run_experiment.jl experiments/main/grid.toml [--only tag=ct_out30] [--dry-run] [--checkpoint]
```

Each experiment writes `<output_dir>/<tag>/result.jld2` ([`save_result`](@ref)),
`constants.csv`, `prcout.csv` and `provenance.toml`.

## Adding an experiment

Copy a TOML file and change it. A new model variant needs a new [`ModelOptions`](@ref)
field (and its implementation in `src/model/`), plus a test. A new acceptance criterion
needs a new [`AcceptanceRule`](@ref) subtype with an [`accepts`](@ref) method; the
engine does not change.

## Running on a cluster

Set the number of threads with `julia -t N` (or `JULIA_NUM_THREADS`). Use
`--checkpoint` for long jobs. To split one experiment across nodes, run with
different `--only` filters, or give each node its own seed with `[grid] seeds = [...]`
and combine the results with [`merge_results`](@ref).
