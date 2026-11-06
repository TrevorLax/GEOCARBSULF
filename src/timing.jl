# Optional timing instrumentation of the precalibration engine, for the benchmark in
# benchmark/timing (TIMING_BENCHMARK_PLAN.md §6.8).
#
# The sections are written with `TimerOutputs.@timeit_debug`. They compile to nothing
# until someone calls
#
#     using TimerOutputs
#     TimerOutputs.enable_debug_timings(GeocarbPrecalibration)
#
# after which the methods are recompiled with the timers and the times accumulate in
# `GeocarbPrecalibration.TIMER` (print it, or `TimerOutputs.reset_timer!` it).
# The timer is shared: enable it only for single-threaded runs (`max_parallel = 1`),
# because concurrent chunks would update it at the same time.

"Timer of the instrumented sections; see `src/timing.jl`. Not part of the public API."
const TIMER = TimerOutput()
