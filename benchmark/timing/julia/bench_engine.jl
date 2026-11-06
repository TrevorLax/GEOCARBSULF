# bench_engine.jl: Julia side of the precalibration engine (plan §3.5)
#   mode = fixed       E2 fixed work for the variants J0..J3, then the E1 breakdown
#                      (TimerOutputs sections of run_precalibration, enabled only now) and
#                      the instrumentation check (identical results, overhead)
#   mode = realistic   E3 stop after n_accept_min accepted samples
#   mode = threads     E4 one thread count per process; the result fingerprint must be
#                      identical for every thread count (checked by collect.jl)
#   mode = memory      E5 one configuration per process: design × covariances, first chunk only
#   mode = checkpoint  E6 with and without checkpoint_dir

include(joinpath(@__DIR__, "..", "lib", "common.jl"))
job = read_job(ARGS[1])
w = RawWriter(job)
using GeocarbPrecalibration
using TimerOutputs
const GP = GeocarbPrecalibration

mode = jstr(job, "mode", "fixed")
seed = jint(job, "seed", 2026)
tmp = jstr(job, "tmp_dir"); mkpath(tmp)

# J0: parity (global LHS, inverse Wishart, covariances kept, 1 thread)
# J1: v1 defaults (chunked LHS, inverse Wishart, no covariances, 1 thread)
# J2: J1 with all threads; J3: J2 with the multivariate-t sampler
const VARIANTS = Dict(
    "J0" => (constant_design = :global_lhs, time_sampler = :inverse_wishart, save_covariances = true, threads = 1),
    "J1" => (constant_design = :chunked_lhs, time_sampler = :inverse_wishart, save_covariances = false, threads = 1),
    "J2" => (constant_design = :chunked_lhs, time_sampler = :inverse_wishart, save_covariances = false, threads = 0),
    "J3" => (constant_design = :chunked_lhs, time_sampler = :multivariate_t, save_covariances = false, threads = 0),
)
nthreads_of(v) = VARIANTS[v].threads == 0 ? Threads.nthreads() : VARIANTS[v].threads

config(v, n, chunk, threshold, n_min) = ExperimentConfig(; name = "timing", tag = "timing_$v", constraint = :both,
    threshold = threshold, n_sample = n, n_per_chunk = chunk, n_accept_min = n_min, seed = seed,
    constant_design = VARIANTS[v].constant_design, time_sampler = VARIANTS[v].time_sampler,
    save_covariances = VARIANTS[v].save_covariances)

runpc(cfg, threads; kw...) = run_precalibration(cfg; max_parallel = threads, verbose = false, kw...)

# Garbage left by the previous run (e.g. J0's covariances) must not be collected inside the
# next timed run.
function measure_gc(f)
    GC.gc(true)
    t = @timed f()
    compile = hasproperty(t, :compile_time) ? Float64(t.compile_time) : NaN
    return (wall = Float64(t.time), gc = Float64(t.gctime), compile = compile, bytes = Int(t.bytes), value = t.value)
end

fingerprint(r) = string(hash((r.constants, r.co2, r.temp, r.time_series, r.prcout_co2, r.prcout_temp, r.n_simulated)); base = 16)

chunk_for(n, chunk) = min(chunk, cld(n, 2))       # same chunk sizes as the R engine (at least two chunks)

warmup(v) = runpc(config(v, 200, 100, 0.5, 201), nthreads_of(v))

if mode == "fixed"
    thr = jfloat(job, "threshold")
    variants = jlist(job, "variants")
    for v in variants
        warmup(v)
    end
    timed_n = Int[]
    for n in jints(job, "sizes"), v in variants
        ch = chunk_for(n, jint(job, "chunk"))
        wl = "n=$n chunk=$ch threshold=$thr"
        need = julia_engine_bytes(n, ch; global_lhs = VARIANTS[v].constant_design == :global_lhs,
                                  covariances = VARIANTS[v].save_covariances, threads = nthreads_of(v))
        if need > jfloat(job, "memory_limit_bytes")
            record!(w; variant = v, component = "E2", workload = wl, n = n, wall_s = NaN, threads = nthreads_of(v),
                    notes = "skipped by the memory guard (about $(round(need / 1e9; digits = 1)) GB)")
            continue
        end
        component!(w, v, "E2"; workload = wl) do
            # warm-up with the same threshold and chunk size (two chunks): a warm-up with other
            # settings left about 0.3 s of compilation inside the first timed run
            nw = min(n, 2ch)
            runpc(config(v, nw, ch, thr, nw + 1), nthreads_of(v))
            m = measure_gc(() -> runpc(config(v, n, ch, thr, n + 1), nthreads_of(v)))
            r = m.value
            check(r.n_simulated == n, "fixed work: n_simulated = $(r.n_simulated), expected $n")
            record!(w, m; variant = v, component = "E2", subcomponent = "run_precalibration", workload = wl, n = n,
                    threads = nthreads_of(v), peak_rss_bytes = peak_rss(),
                    notes = "accepted $(n_accepted(r)); fingerprint=$(fingerprint(r))")
        end
        v == "J1" && push!(timed_n, n)
    end
    # E1: instrumented runs of J1 (and J0 when requested), single thread, after the plain runs
    TimerOutputs.enable_debug_timings(GP)
    for v in intersect(variants, ["J1", "J0"]), n in jints(job, "sizes")
        ch = chunk_for(n, jint(job, "chunk"))
        wl = "n=$n chunk=$ch threshold=$thr"
        julia_engine_bytes(n, ch; global_lhs = v == "J0", covariances = v == "J0") > jfloat(job, "memory_limit_bytes") && continue
        component!(w, v, "E1"; workload = wl) do
            cfg = config(v, n, ch, thr, n + 1)
            runpc(config(v, 200, 100, 0.5, 201), 1)               # compile the instrumented methods
            plain = runpc(cfg, 1)
            GC.gc(true)
            TimerOutputs.reset_timer!(GP.TIMER)
            t = @elapsed (timed = runpc(cfg, 1))
            check(fingerprint(plain) == fingerprint(timed), "instrumented run gives a different result")
            to = GP.TIMER
            total = TimerOutputs.tottime(to) / 1e9
            inner = 0.0
            for (name, sec) in to.inner_timers
                s = TimerOutputs.time(sec) / 1e9
                inner += s
                record!(w; variant = v, component = "E1", subcomponent = name, workload = wl, n = n, threads = 1, wall_s = s,
                        alloc_bytes = Int(TimerOutputs.allocated(sec)), notes = "calls $(TimerOutputs.ncalls(sec))")
            end
            record!(w; variant = v, component = "E1", subcomponent = "orchestration (not in a section)", workload = wl, n = n,
                    threads = 1, wall_s = t - inner, notes = "run_precalibration wall minus the sections")
            record!(w; variant = v, component = "E2", subcomponent = "run_precalibration (instrumented)", workload = wl, n = n,
                    threads = 1, wall_s = t)
        end
    end
    TimerOutputs.disable_debug_timings(GP)

elseif mode == "realistic"
    for pair in jlist(job, "realistic"), v in jlist(job, "variants")
        thr_s, k_s, cap_s = split(pair, ":"); thr = parse(Float64, thr_s); k = parse(Int, k_s); cap = parse(Int, cap_s)
        ch = jint(job, "chunk")
        wl = "threshold=$(thr == round(thr; digits = 2) ? string(thr) : thr) accept=$k chunk=$ch cap=$cap"
        component!(w, v, "E3"; workload = wl) do
            # warm-up = the timed call itself: warmup(v) (other chunk size and threshold) left about
            # 0.3 s of compilation inside the timed run (smoke run 2026-11-06: 0.42 s for 500 samples
            # against 0.16 s for 1000 in E1)
            runpc(config(v, cap, ch, thr, k), nthreads_of(v))
            m = measure_gc(() -> runpc(config(v, cap, ch, thr, k), nthreads_of(v)))
            r = m.value
            check(n_accepted(r) == k, "only $(n_accepted(r)) of $k accepted within n_sample = $cap (lower realistic_min_rate)")
            record!(w, m; variant = v, component = "E3", subcomponent = "run_precalibration", workload = wl,
                    n = r.n_simulated, threads = nthreads_of(v), peak_rss_bytes = peak_rss(),
                    notes = "n_simulated=$(r.n_simulated) n_accepted=$(n_accepted(r))")
        end
    end

elseif mode == "threads"
    n = jint(job, "n"); ch = jint(job, "chunk"); thr = jfloat(job, "threshold")
    wl = "n=$n chunk=$ch threshold=$thr"
    component!(w, "J2", "E4"; workload = wl) do
        runpc(config("J2", min(n, 2ch), ch, thr, min(n, 2ch) + 1), Threads.nthreads())   # same settings, two chunks
        m = measure_gc(() -> runpc(config("J2", n, ch, thr, n + 1), Threads.nthreads()))
        record!(w, m; variant = "J2", component = "E4", subcomponent = "run_precalibration", workload = wl, n = n,
                threads = Threads.nthreads(), peak_rss_bytes = peak_rss(), notes = "fingerprint=$(fingerprint(m.value))")
    end

elseif mode == "memory"
    n = jint(job, "n"); ch = jint(job, "chunk")
    design = Symbol(jstr(job, "design")); cov = jbool(job, "covariances")
    wl = "$(design) n=$n chunk=$ch covariances=$(cov ? "on" : "off")"
    component!(w, "J1", "E5"; workload = wl) do
        cfg = ExperimentConfig(; name = "memory", tag = "memory", constraint = :both, threshold = 1.0, n_sample = n,
                               n_per_chunk = ch, n_accept_min = ch, seed = seed, constant_design = design,
                               time_sampler = :inverse_wishart, save_covariances = cov)
        m = measure_gc(() -> runpc(cfg, 1))
        record!(w, m; variant = design == :global_lhs ? "J0" : "J1", component = "E5",
                subcomponent = "peak memory, constants + first chunk", workload = wl, n = n, threads = 1,
                peak_rss_bytes = peak_rss())
    end

elseif mode == "checkpoint"
    n = jint(job, "n"); ch = jint(job, "chunk"); thr = jfloat(job, "threshold")
    wl = "n=$n chunk=$ch threshold=$thr"
    component!(w, "J1", "E6"; workload = wl) do
        cfg = config("J1", n, ch, thr, n + 1)
        # warm-up of both code paths with the same settings (two chunks), so that neither the run
        # nor the checkpoint writer (JLD2) is compiled inside a timed run
        cw = config("J1", min(n, 2ch), ch, thr, min(n, 2ch) + 1)
        runpc(cw, 1)
        wdir = mktempdir(tmp); runpc(cw, 1; checkpoint_dir = wdir); runpc(cw, 1; checkpoint_dir = wdir)
        rm(wdir; recursive = true, force = true)
        a = measure_gc(() -> runpc(cfg, 1))
        dir = mktempdir(tmp)
        b = measure_gc(() -> runpc(cfg, 1; checkpoint_dir = dir))
        c = measure_gc(() -> runpc(cfg, 1; checkpoint_dir = dir))         # every chunk read back
        check(fingerprint(a.value) == fingerprint(b.value) == fingerprint(c.value), "checkpointing changed the result")
        record!(w, a; variant = "J1", component = "E6", subcomponent = "no checkpoint", workload = wl, n = n, threads = 1)
        record!(w, b; variant = "J1", component = "E6", subcomponent = "writing checkpoints", workload = wl, n = n, threads = 1)
        record!(w, c; variant = "J1", component = "E6", subcomponent = "resuming from checkpoints", workload = wl, n = n, threads = 1)
        rm(dir; recursive = true, force = true)
    end
end
