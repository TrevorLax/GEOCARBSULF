# Performance

How fast the Julia port is, compared with the original R/Fortran code, is measured by
the timing benchmark in `benchmark/timing` (plan: `TIMING_BENCHMARK_PLAN.md`; usage:
`benchmark/timing/README.md`). It times every stage of the workflow in both
implementations on the same machine, checks the results of every timed block, and
writes a report with medians, interquartile ranges and 95 % bootstrap intervals for the
speed-ups.

```text
run_timing.bat --suite quick          (Windows)
julia --project=benchmark/timing benchmark/timing/run_timing.jl --suite quick
```

No numbers are given on this page yet: they depend on the machine, and the reference
numbers will be taken from a `standard` run on the machine that ran the legacy
comparison. When they are added, they will come with that run's `env.toml` (CPU, RAM,
OS, Julia and R versions, BLAS, gfortran flags, power plan and antivirus state).

## What is measured

| family | what | plan IDs |
|:--|:--|:--|
| start-up | fresh process, package loading, input set-up, first model call, first figure | S1-S3, G1 |
| model | the model alone (Julia vs the Fortran library called directly), R's wrapper layers, supplemental variants, cost per sample against solver iterations, model options, Fortran build flags | M1-M6 |
| sampling | Latin hypercube, prior transform, time-series samplers by stage, covariance storage, raw RNG | P1-P5 |
| constraints | % outbound, acceptance | C1-C2 |
| engine | fixed-work precalibration and where its time goes, realistic stopping, threads, peak memory, checkpoints | E1-E6 |
| I/O | saving and loading results | O1-O3 |
| analysis and figures | the numerical sections and the figures of `analysis_and_plots.R` on a shared ensemble | A1-A6, G2-G3 |
| end to end | set-up, precalibration, save, analysis and figures in one fresh process | X1 |

## Instrumentation in the package

`run_precalibration` contains timing sections written with
`TimerOutputs.@timeit_debug`. They compile to nothing unless switched on:

```julia
using GeocarbPrecalibration, TimerOutputs
TimerOutputs.enable_debug_timings(GeocarbPrecalibration)
run_precalibration(cfg; max_parallel = 1)
GeocarbPrecalibration.TIMER          # the accumulated sections
TimerOutputs.disable_debug_timings(GeocarbPrecalibration)
```

Use them with one thread only: the timer is shared between chunks.
