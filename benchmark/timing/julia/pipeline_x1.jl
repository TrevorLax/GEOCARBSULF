# pipeline_x1.jl: end-to-end run for X1 (plan §3.9), started in a fresh process by
# run_timing.jl (which measures the whole process from outside):
#   setup + precalibration (CO2 + temperature, stop after n_accept accepted) -> save ->
#   analysis and figures on the shared ensemble (as the R pipeline must: finding N-2)
t_load = @elapsed using GeocarbPrecalibration
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
job = read_job(ARGS[1])
w = RawWriter(job)
include(joinpath(@__DIR__, "..", "lib", "analysis_julia.jl"))
v = jstr(job, "variant")
thr = jfloat(job, "threshold");
k = jint(job, "n_accept");
ch = jint(job, "chunk");
seed = jint(job, "seed");
out = mkpath(jstr(job, "tmp_dir"))
wl = "threshold=$thr accept=$k"
designs = Dict(
    "J0" => (:global_lhs, :inverse_wishart, true),
    "J1" => (:chunked_lhs, :inverse_wishart, false),
    "J2" => (:chunked_lhs, :inverse_wishart, false),
    "J3" => (:chunked_lhs, :multivariate_t, false),
)
d = designs[v]
threads = v in ("J2", "J3") ? Threads.nthreads() : 1
function stage(name, t; kw...)
    return record!(
        w; variant=v, component="X1", subcomponent=name, workload=wl, threads=threads, mode="cold", wall_s=t, kw...
    )
end
stage("load package", t_load)
cfg = ExperimentConfig(;
    name="x1",
    tag="x1",
    constraint=:both,
    threshold=thr,
    n_sample=jint(job, "n_cap"),
    n_per_chunk=ch,
    n_accept_min=k,
    seed=seed,
    constant_design=d[1],
    time_sampler=d[2],
    save_covariances=d[3],
    output_dir=out,
)
t = @elapsed r = run_precalibration(cfg; max_parallel=threads, verbose=false)
check(n_accepted(r) == k, "X1: only $(n_accepted(r)) accepted")
stage("precalibration", t; n=r.n_simulated, notes="n_simulated=$(r.n_simulated)")
f = joinpath(out, "result.jld2")
t = @elapsed (save_result(f, r); write_summary_csvs(joinpath(out, "summary"), r))
stage("save", t)
st = SectionTimer(w, v, wl, k)
ens = jstr(job, "ensemble_jld2")
t = @elapsed res = julia_analysis!(
    st, tag -> load_result(ens), jint(job, "num_samples"); figdir=joinpath(out, "figures")
)
stage("analysis", t)
t = @elapsed @eval using CairoMakie
stage("figures: using CairoMakie", t)
st2 = SectionTimer(w, v, wl, k)
t = @elapsed draw_figures!(st2, res["figures"], res["figdir"], CairoMakie.save; mode="cold")
stage("figures", t)
