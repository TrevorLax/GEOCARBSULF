# bench_analysis.jl: Julia side of analysis (A1-A6) and graphics (G2, G3) on the shared
# ensemble (plan §3.7-3.8, §5.3). Every experiment tag loads the same ensemble file, as the
# R side does, so both implementations analyse identical samples.
# Pass 1 runs cold (includes compilation, recorded as mode = first_call); pass 2 is warm.

include(joinpath(@__DIR__, "..", "lib", "common.jl"))
job = read_job(ARGS[1])
w = RawWriter(job)
t_pkg = @elapsed using GeocarbPrecalibration
include(joinpath(@__DIR__, "..", "lib", "analysis_julia.jl"))

ens = jstr(job, "ensemble_jld2")
num = jint(job, "num_samples")
figroot = jstr(job, "fig_dir")
out_dir = jstr(job, "out_dir");
mkpath(out_dir);
wl = "ensemble n=$num, 15 experiments"
loader(tag) = load_result(ens)

t_makie = @elapsed using CairoMakie
record!(
    w;
    variant="J",
    component="G1",
    subcomponent="using CairoMakie (in process)",
    mode="first_call",
    wall_s=t_makie,
    workload=wl,
)

numbers = nothing
for pass in 1:2
    mode = pass == 1 ? "first_call" : "warm"
    st = SectionTimer(w, "J", wl, num)
    component!(w, "J", "A"; workload=wl) do
        res = julia_analysis!(st, loader, num; figdir=joinpath(figroot, "julia_pass$pass"))
        flush_sections!(st; mode=mode)
        draw_figures!(st, res["figures"], res["figdir"], CairoMakie.save; mode=mode)
        global numbers = res
    end
end

# numbers for the cross-check with R in collect.jl (same ensemble, no subsampling for c_out30)
open(joinpath(out_dir, "julia_numbers_rep$(w.rep).csv"), "w") do io
    println(io, "quantity,value")
    q = numbers["deltaT2X_quantiles_c_out30"]
    for (p, v) in zip(DEFAULT_PROBS, q)
        println(io, "deltaT2X_c_out30_q$(p),", repr(v))
    end
end
