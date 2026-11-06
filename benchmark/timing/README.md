# Timing benchmark: original R/Fortran vs the Julia port

Implements `TIMING_BENCHMARK_PLAN.md` (in the project documents). It times every stage of
the workflow (start-up, model, sampling, constraints, the precalibration engine, file
I/O, analysis, figures, end to end) in both implementations, on the same machine, with
the same inputs where the work is deterministic, and checks the results of every timed
block.

## Running it

On Windows, double-click or run from the repository folder:

```text
run_timing.bat                          quick suite, about 20-40 minutes
run_timing.bat --suite smoke            every part once with tiny sizes (10-15 min; checks the set-up)
run_timing.bat --suite standard         about 2-3 hours
run_timing.bat --suite full             overnight
run_timing.bat --suite quick --only model,engine
```

Elsewhere, or by hand:

```text
julia --project=benchmark/timing -e "using Pkg; Pkg.instantiate()"
julia --project=benchmark/timing benchmark/timing/run_timing.jl --suite quick [options]
```

Options: `--reps N`, `--only FAMILY,...`, `--out DIR`, `--rscript PATH`, `--skip-r`,
`--skip-julia`, `--allow-synced`, `--keep-work`, `--install-r-packages`, `--dry-run`
(prints every process it would start). See the header of `run_timing.jl`.

**Before a run** (plan §6.1): mains power, "Best performance" power mode, other
programs closed. Antivirus real-time protection stays as it is (decision T6, option A);
its state is recorded in `env.toml`. Keep long runs away from the scheduled scan time
(also in `env.toml`).

**Prerequisite:** the legacy-comparison exports in `test/legacy_comparison/output`
(run `run_tests.bat` first). Speed is only measured on a version that passes parity.

## Output

Results go to `%LOCALAPPDATA%\GeocarbTiming\<computer>_<date-time>\`, which is **not**
inside the synced folder; the harness refuses a synced results folder unless
`--allow-synced` is given.

| file | content |
|:--|:--|
| `report.md` | summary table (ratios with 95 % bootstrap intervals), E1 breakdown, per-sample model cost, R overhead, Fortran build variants, scaling, threads, memory, cold start, figures, end to end, projection, hypotheses H1-H8, caveats |
| `timings.csv` | median, quartiles and minimum per measurement |
| `raw/*.csv` | one row per measurement (schema of plan §7); `*_per_sample.csv` for M4 |
| `env.toml` | machine, OS, power plan, antivirus state, Julia/R versions, BLAS, gfortran and flags, library hashes |
| `session.toml` | suite, options and the configuration used |
| `logs/` | the output of every process |
| `figures/`, `report_figures/` | the figures drawn by the analysis benchmark; the report's charts (E1 breakdown, M4 cost per sample; the other results are tables) |

## How it is organised

```
benchmark/timing/
├── run_timing.jl       orchestrator: fresh process per measurement, R and Julia interleaved in random order
├── config.toml         suites (smoke, quick, standard, full), sizes, memory guard, Fortran variants
├── collect.jl          raw CSVs -> timings.csv, report.md, report_figures/
├── lib/common.jl       job files, raw writer, timers, guards, memory guard (Julia)
├── lib/common.R        the same for R, plus the legacy set-up and code-block helpers
├── lib/analysis_julia.jl   Julia counterparts of the timed sections of analysis_and_plots.R
├── env/capture_env.jl  env.toml
├── calibration/        drift sentinels (sentinel.jl, sentinel.R)
├── julia/              bench_model, bench_sampling, bench_constraints, bench_engine, bench_io,
│                       bench_analysis, startup_probe, pipeline_x1, prepare_ensemble
└── r/                  the same in R, plus instrumented/make_instrumented.R
```

| family | components (plan §3) | R side | Julia side |
|:--|:--|:--|:--|
| startup | S1, S0 (probe), S2, S3, G1, S1b | fresh `Rscript` processes | fresh `julia` processes |
| model | M1/H0, M2, M3, M4, M5, M6 | `model_run`, `run_geocarbF`, bare `.Fortran` | `run_geocarb!` and the Fortran library through `ccall` |
| sampling | P1-P5 | the code of `lhs_sampling.R` itself | `random_lhs`, `transform_unit`, samplers |
| constraints | C1, C2 | `percout`, the acceptance block of `lhs_sampling.R` | `legacy_percent_outbound`, `accepts` |
| engine | E1-E6, B3 | generated `lhs_timed.R` / `lhs_sampling_timed.R` | `run_precalibration` (J0-J3), `@timeit_debug` sections |
| io | O1-O3 | `save()` / `load()` of the lhs.R objects | `save_result`, `load_result`, RData.jl |
| analysis | A1-A6, G2, G3 | generated `analysis_and_plots_timed.R` | `lib/analysis_julia.jl` + `GeocarbMakieExt` |
| endtoend | X1 | `pipeline_x1.R` | `pipeline_x1.jl` (J1, J2, J3) |

Variants: R0 (R + the library in `legacy/fortran`), R1 (R + an `-O3` build), H0 (Fortran
called directly from Julia), J0 (parity: global LHS, covariances kept, 1 thread), J1
(defaults, 1 thread), J2 (all threads), J3 (all threads, multivariate-t sampler).

## Rules the harness enforces

- **Legacy code is not edited.** Fortran variants are built into the results folder;
  R variants run from copies of `legacy/R` there. The instrumented R scripts are
  generated at every run from the files in `legacy/R` by
  `r/instrumented/make_instrumented.R`; each edit is anchored on an exact line and the
  generator stops if an anchor is missing, so the copies cannot drift silently.
- **The timers do not change results.** The engine family runs the original and the
  instrumented R code with the same seed and requires every saved object to be
  `identical()`; the analysis family does the same for its copy. The Julia timers
  (`TimerOutputs.@timeit_debug`, compiled out unless switched on) are checked by
  comparing result fingerprints.
- **Every timed block is checked** against the legacy exports or invariants (Inf/NaN
  masks, values within the parity tolerances, % outbound, accepted counts, bounds,
  present-day normalisation). A failed check removes the timing from the report and is
  listed there.
- **Memory guard:** runs projected above 70 % of RAM are skipped and reported.

## Known limits of this version

- The shared ensemble analysed in the A/G families is generated by the Julia port
  (`julia/prepare_ensemble.jl`, CO2 + temperature at 50 %) and converted to `.RData`
  for R, because the paper's `.RData` outputs are not in the repository. Both sides
  read identical samples; every experiment tag reads the same ensemble.
- E3 (realistic stopping) and X1 use the 50 % threshold; at 30 % the acceptance rate is
  too low for R to finish in a reasonable time (0 of 1000 prior draws pass).
- Not implemented: X2 (supplemental pipeline), X3 (Cretaceous pipeline), the
  supplemental/Cretaceous part of the analysis, G1 with a PrecompileTools workload or a
  sysimage, an R build with an optimised BLAS (T7). S1b compiles the package only.
- The Julia side of `deltaT2X_samplesize.pdf` and `co2_and_uncertainties.pdf` does not
  exist yet; those figures appear as R-only rows.
