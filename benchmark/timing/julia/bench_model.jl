# bench_model.jl: Julia side of the model components (plan §3.2)
#   M1/H0  pure model compute: run_geocarb! vs the Fortran library called with ccall
#          (no R involved), interleaved sample by sample, for every library variant
#   M2     Julia wrapper costs: allocating run_geocarb vs run_geocarb!, constants from a vector
#   M3     supplemental configurations (Julia ModelOptions vs run_geocarb_supp_ via ccall)
#   M4     per-sample times with solver iterations and failed steps (per-sample file)
#   M5     model-option cost (Julia only)

include(joinpath(@__DIR__, "..", "lib", "common.jl"))
job = read_job(ARGS[1])
w = RawWriter(job)
using GeocarbPrecalibration
const GP = GeocarbPrecalibration
include_legacy_helpers()              # legacy_samples, read_matrix, fortran_* (test/legacy_comparison)

exports = jstr(job, "exports_dir")
n_inputs = jint(job, "model_inputs", 1001)
n_supp = jint(job, "supp_inputs", 200)
exact_variant = jstr(job, "exact_variant", "")   # library that produced the exports: compare exactly
libs = [split(x, "|") for x in jlist(job, "fortran_libs")]   # name|main path|supp path

tp = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
const age = tp.center.age
samples = legacy_samples(exports, age)
n_main = min(length(samples), n_inputs - 1)
table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
const inputs = vcat([(mean_constants(table), copy(tp.center))], samples[1:n_main])   # sample 0 = prior means
_, co2_ref = read_matrix(joinpath(exports, "legacy_co2.csv"))
_, temp_ref = read_matrix(joinpath(exports, "legacy_temp_plus15.csv"))
_, center_ref = read_matrix(joinpath(exports, "legacy_center_run.csv"))
groups, nfail = sample_groups(co2_ref)
const ref_co2 = vcat(permutedims(center_ref[:, 2]), co2_ref[1:n_main, :])
group_of(k) = k == 1 ? "prior_mean" : groups[k - 1]
nfail_of(k) = k == 1 ? 0 : nfail[k - 1]
const nt = length(age)
const opts = ModelOptions()                 # fortran_single_literals = true: the compiled Fortran's arithmetic

# --- Fortran through ccall, without allocation in the timed call --------------------
struct FArgs
    m56::Vector{Float64}
    m12::Matrix{Float64}
    age::Vector{Float64}
    co2::Vector{Float64}
    o2::Vector{Float64}
    temp::Vector{Float64}
end
function FArgs(p, f)
    return FArgs(
        Float64.(parameter_vector(p)),
        Float64.(GP.forcing_matrix(f)),
        copy(f.age),
        fill(-999.99, length(f.age)),
        fill(-999.99, length(f.age)),
        fill(-999.99, length(f.age)),
    )
end

@inline function fortran_run!(fptr::Ptr{Cvoid}, a::FArgs, itmax::Int32)
    fill!(a.co2, -999.99)
    fill!(a.o2, -999.99)
    fill!(a.temp, -999.99)
    ccall(
        fptr,
        Cvoid,
        (Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ref{Int32}, Ref{Int32}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}),
        a.m56,
        a.m12,
        a.age,
        Int32(length(a.age)),
        itmax,
        a.co2,
        a.o2,
        a.temp,
    )
    return a
end

@inline function fortran_run_supp!(fptr::Ptr{Cvoid}, a::FArgs, cfg, itmax::Int32)
    fill!(a.co2, -999.99)
    fill!(a.o2, -999.99)
    fill!(a.temp, -999.99)
    ccall(
        fptr,
        Cvoid,
        (
            Ptr{Float64},
            Ptr{Float64},
            Ref{Float64},
            Ref{Float64},
            Ref{Float64},
            Ref{Float64},
            Ptr{Float64},
            Ref{Int32},
            Ref{Int32},
            Ptr{Float64},
            Ptr{Float64},
            Ptr{Float64},
        ),
        a.m56,
        a.m12,
        cfg[1],
        cfg[2],
        cfg[3],
        cfg[4],
        a.age,
        Int32(length(a.age)),
        itmax,
        a.co2,
        a.o2,
        a.temp,
    )
    return a
end

const fargs = [FArgs(p, f) for (p, f) in inputs]
const outs = [GeocarbResult{Float64}(age) for _ in inputs]
const itmax = Int32(10)

const loaded = Tuple{String,Ptr{Cvoid},Ptr{Cvoid}}[]
for l in libs
    pm = fortran_symbol(l[2], :run_geocarb_)
    ps = length(l) >= 3 && !isempty(l[3]) ? fortran_symbol(l[3], :run_geocarb_supp_) : nothing
    if pm === nothing
        record!(
            w;
            impl="fortran",
            variant="H0_" * l[1],
            component="M1",
            wall_s=NaN,
            checksum_ok=false,
            notes="library could not be loaded: $(l[2])",
        )
    else
        push!(loaded, (String(l[1]), pm, ps === nothing ? C_NULL : ps))
    end
end

# warm-up (compiles run_geocarb! and the ccall wrappers)
for k in eachindex(inputs)
    run_geocarb!(outs[k], inputs[k]...; options=opts)
end
for (_, pm, _) in loaded, k in 1:min(50, length(fargs))
    fortran_run!(pm, fargs[k], itmax)
end

# --- M1 + M4: interleaved per-sample timing ------------------------------------------
component!(w, "J", "M1"; workload="legacy_$(length(inputs))") do
    nl = length(loaded)
    tj = zeros(length(inputs))
    tf = zeros(length(inputs), nl)
    co2j = Matrix{Float64}(undef, length(inputs), nt)
    co2f = [similar(co2j) for _ in 1:nl]
    order = Random.shuffle(Random.Xoshiro(jint(job, "rep", 1)), collect(eachindex(inputs)))
    for k in order
        p, f = inputs[k]
        t0 = time_ns()
        run_geocarb!(outs[k], p, f; options=opts)
        tj[k] = (time_ns() - t0) / 1e9
        co2j[k, :] .= outs[k].co2
        for (j, (_, pm, _)) in enumerate(loaded)
            t0 = time_ns()
            fortran_run!(pm, fargs[k], itmax)
            tf[k, j] = (time_ns() - t0) / 1e9
            co2f[j][k, :] .= fargs[k].co2
        end
    end
    check_outputs("Julia run_geocarb! co2", co2j, ref_co2)
    record!(
        w;
        variant="J",
        component="M1",
        subcomponent="run_geocarb!",
        workload="legacy_$(length(inputs))",
        n=length(inputs),
        wall_s=sum(tj) / length(tj),
        threads=1,
        notes="seconds per call (mean)",
    )
    for k in eachindex(inputs)
        record_per_sample!(w, "J", "M4", k - 1, group_of(k), sum(outs[k].iterations), nfail_of(k), tj[k])
    end
    for (j, (name, _, _)) in enumerate(loaded)
        check_outputs("Fortran $name co2", co2f[j], ref_co2; exact=name == exact_variant)
        record!(
            w;
            impl="fortran",
            variant="H0_" * name,
            component="M1",
            subcomponent="ccall run_geocarb_",
            workload="legacy_$(length(inputs))",
            n=length(inputs),
            wall_s=sum(view(tf, :, j)) / size(tf, 1),
            threads=1,
            notes="seconds per call (mean)",
        )
        for k in eachindex(inputs)
            # the Fortran exposes no iteration count; its Inf masks equal Julia's, so Julia's counts apply
            open(w.per_sample_path, "a") do io
                println(
                    io,
                    join(
                        _csvfield.(
                            Any[
                                "fortran",
                                "H0_" * name,
                                "M4",
                                w.rep,
                                k - 1,
                                group_of(k),
                                sum(outs[k].iterations),
                                nfail_of(k),
                                tf[k, j],
                                w.session,
                            ]
                        ),
                        ",",
                    ),
                )
            end
        end
    end
end

# --- M1 batch throughput (blocks of ≥ 50 ms, as the per-sample timer has ~30 ns overhead)
component!(w, "J", "M1-batch") do
    passes = 3
    for _ in 1:passes
        t = per_call(() -> (
            for k in eachindex(inputs)
                run_geocarb!(outs[k], inputs[k]...; options=opts)
            end
        ), 1)
        record!(
            w;
            variant="J",
            component="M1",
            subcomponent="batch run_geocarb!",
            workload="legacy_$(length(inputs))",
            n=length(inputs),
            wall_s=t / length(inputs),
            threads=1,
            notes="seconds per call, whole pass",
        )
        for (name, pm, _) in loaded
            t = per_call(() -> (
                for a in fargs
                    fortran_run!(pm, a, itmax)
                end
            ), 1)
            record!(
                w;
                impl="fortran",
                variant="H0_" * name,
                component="M1",
                subcomponent="batch ccall",
                workload="legacy_$(length(inputs))",
                n=length(fargs),
                wall_s=t / length(fargs),
                threads=1,
                notes="seconds per call, whole pass",
            )
        end
    end
end

# --- M2: Julia-side wrapper costs ----------------------------------------------------
component!(w, "J", "M2") do
    alloc = measure(() -> (
        for (p, f) in inputs
            run_geocarb(p, f; options=opts)
        end
    ))
    inplace = measure(() -> (
        for k in eachindex(inputs)
            run_geocarb!(outs[k], inputs[k]...; options=opts)
        end
    ))
    n = length(inputs)
    record!(
        w;
        variant="J",
        component="M2",
        subcomponent="run_geocarb (allocating)",
        n=n,
        wall_s=alloc.wall / n,
        gc_s=alloc.gc / n,
        alloc_bytes=alloc.bytes ÷ n,
        notes="seconds per call",
    )
    record!(
        w;
        variant="J",
        component="M2",
        subcomponent="run_geocarb! (in place)",
        n=n,
        wall_s=inplace.wall / n,
        gc_s=inplace.gc / n,
        alloc_bytes=inplace.bytes ÷ n,
        notes="seconds per call",
    )
    vecs = [Float64.(parameter_vector(p)) for (p, _) in inputs]
    GP._constants_from_vector(Float64, vecs[1])
    k = calls_for(() -> GP._constants_from_vector(Float64, vecs[1]))
    t = per_call(() -> GP._constants_from_vector(Float64, vecs[1]), k)
    record!(
        w;
        variant="J",
        component="M2",
        subcomponent="ConstantParams from vector",
        n=k,
        wall_s=t,
        notes="seconds per call",
    )
    t = per_call(() -> (
        for (p, f) in inputs
            FArgs(p, f)
        end
    ), 1) / n
    record!(
        w;
        impl="fortran",
        variant="H0",
        component="M2",
        subcomponent="prepare ccall arguments (Julia)",
        n=n,
        wall_s=t,
        notes="seconds per call; outside the M1 timer",
    )
end

# --- M3: supplemental configurations -------------------------------------------------
supp_names = ["control", "gym", "timing", "gym_timing", "dT2X", "gym_timing_dT2X"]
supp_cfg = Dict(
    "control" => (130.0, 80.0, 1.0, -1.0),
    "gym" => (130.0, 80.0, 0.25, -1.0),
    "timing" => (110.0, 60.0, 1.0, -1.0),
    "gym_timing" => (110.0, 60.0, 0.25, -1.0),
    "dT2X" => (130.0, 80.0, 1.0, 1.0),
    "gym_timing_dT2X" => (110.0, 60.0, 0.25, 1.0),
)
supp_opts(c) = ModelOptions(; gym_angio_transition=(c[1], c[2]), gym_factor=c[3], dT2X_ramp=c[4] >= 0)
ns = min(n_supp, n_main)
for nm in supp_names
    component!(w, "J", "M3"; workload=nm) do
        _, ref = read_matrix(joinpath(exports, "legacy_supp_$(nm)_co2.csv"))
        o = supp_opts(supp_cfg[nm])
        sub = 2:(ns + 1)                          # inputs[1] is the prior-mean run
        for k in sub
            run_geocarb!(outs[k], inputs[k]...; options=o)
        end
        t = per_call(() -> (
            for k in sub
                run_geocarb!(outs[k], inputs[k]...; options=o)
            end
        ), 1)
        check_outputs("Julia supp $nm", reduce(vcat, [permutedims(outs[k].co2) for k in sub]), ref[1:ns, :])
        record!(
            w;
            variant="J",
            component="M3",
            subcomponent="run_geocarb! + ModelOptions",
            workload=nm,
            n=ns,
            wall_s=t / ns,
            notes="seconds per call",
        )
        for (name, _, ps) in loaded
            ps == C_NULL && continue
            cfg = supp_cfg[nm]
            for k in sub
                fortran_run_supp!(ps, fargs[k], cfg, itmax)
            end
            t = per_call(() -> (
                for k in sub
                    fortran_run_supp!(ps, fargs[k], cfg, itmax)
                end
            ), 1)
            got = reduce(vcat, [permutedims(copy(fortran_run_supp!(ps, fargs[k], cfg, itmax).co2)) for k in sub])
            check_outputs("Fortran $name supp $nm", got, ref[1:ns, :]; exact=name == exact_variant)
            record!(
                w;
                impl="fortran",
                variant="H0_" * name,
                component="M3",
                subcomponent="ccall run_geocarb_supp_",
                workload=nm,
                n=ns,
                wall_s=t / ns,
                notes="seconds per call",
            )
        end
    end
end

# --- M5: model-option cost (Julia only) ----------------------------------------------
component!(w, "J", "M5") do
    for lit in (true, false), corr in (false, true)
        o = ModelOptions(; fortran_single_literals=lit, corrected_newton_derivative=corr)
        for k in eachindex(inputs)
            run_geocarb!(outs[k], inputs[k]...; options=o)
        end
        t = per_call(() -> (
            for k in eachindex(inputs)
                run_geocarb!(outs[k], inputs[k]...; options=o)
            end
        ), 1)
        iters = sum(sum(outs[k].iterations) for k in eachindex(inputs))
        nf = sum(count(!=(Converged), outs[k].status) for k in eachindex(inputs))
        record!(
            w;
            variant="J",
            component="M5",
            subcomponent="single_literals=$lit corrected_derivative=$corr",
            n=length(inputs),
            wall_s=t / length(inputs),
            notes="seconds per call; total Newton iterations $iters; failed steps $nf",
        )
    end
    # Float32 (informational)
    p32 = [
        (
            ConstantParams(collect(CONSTANT_PARAMETER_NAMES), Float32.(parameter_vector(p))),
            TimeForcings(f.age, Dict(n => Float32.(getfield(f, n)) for n in TIME_FORCING_NAMES); check_finite=false),
        ) for (p, f) in inputs
    ]
    o32 = [GeocarbResult{Float32}(age) for _ in inputs]
    for k in eachindex(p32)
        run_geocarb!(o32[k], p32[k]...; options=opts)
    end
    t = per_call(() -> (
        for k in eachindex(p32)
            run_geocarb!(o32[k], p32[k]...; options=opts)
        end
    ), 1)
    record!(
        w;
        variant="J",
        component="M5",
        subcomponent="Float32 inputs",
        n=length(p32),
        wall_s=t / length(p32),
        notes="seconds per call; informational, results not checked",
    )
end
