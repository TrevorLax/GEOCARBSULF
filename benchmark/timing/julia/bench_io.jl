# bench_io.jl: Julia side of output I/O (plan §3.6)
#   O1  save_result (JLD2) and write_summary_csvs, with and without covariances; file sizes
#   O2  load_result; RData.jl load of the R .RData files of the shared ensemble (if given)
#   O3  the same save into a cloud-synced folder (only if synced_dir is set)
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
job = read_job(ARGS[1])
w = RawWriter(job)
using GeocarbPrecalibration

n = jint(job, "io_n")
tmp = jstr(job, "tmp_dir"); mkpath(tmp)
synced = jstr(job, "synced_dir", "")
dirsize(d) = sum(filesize(joinpath(r, f)) for (r, _, fs) in walkdir(d) for f in fs; init = 0)

for cov in (true, false)
    v = cov ? "J0" : "J1"
    wl = "n=$n accepted, covariances=$(cov ? "on" : "off")"
    cfg = ExperimentConfig(; name = "io", tag = "io", constraint = :both, threshold = 1.0, n_sample = n,
                           n_per_chunk = min(1000, cld(n, 2)), n_accept_min = n, seed = 1,
                           constant_design = cov ? :global_lhs : :chunked_lhs, save_covariances = cov)
    r = run_precalibration(cfg; verbose = false, max_parallel = 1)
    small = run_precalibration(with_overrides(cfg; n_sample = 20, n_per_chunk = 10, n_accept_min = 20); verbose = false)
    save_result(joinpath(tmp, "warmup.jld2"), small); load_result(joinpath(tmp, "warmup.jld2"))
    write_summary_csvs(joinpath(tmp, "warmup_csv"), small)
    for (where, root) in (("local", tmp), ("synced", synced))
        isempty(root) && continue
        comp = where == "local" ? "O1" : "O3"
        component!(w, v, comp; workload = wl) do
            d = mkpath(joinpath(root, "GeocarbTiming_io_$(w.session)_$(v)"))
            f = joinpath(d, "result.jld2")
            m = measure(() -> save_result(f, r))
            record!(w, m; variant = v, component = comp, subcomponent = "save_result (JLD2)", workload = wl, n = n,
                    notes = "file $(filesize(f)) bytes; $where")
            m = measure(() -> write_summary_csvs(joinpath(d, "summary"), r))
            record!(w, m; variant = v, component = comp, subcomponent = "write_summary_csvs", workload = wl, n = n,
                    notes = "files $(dirsize(joinpath(d, "summary"))) bytes; $where")
            if where == "local"
                m = measure(() -> load_result(f))
                check(m.value.constants == r.constants && isequal(m.value.co2, r.co2), "load_result changed the data")
                record!(w, m; variant = v, component = "O2", subcomponent = "load_result (JLD2)", workload = wl, n = n)
            end
            rm(d; recursive = true, force = true)
        end
    end
end

rdata = jlist(job, "rdata_files")
if !isempty(rdata)
    @eval using RData
    component!(w, "J", "O2"; workload = "R ensemble .RData") do
        for f in rdata
            Base.invokelatest(RData.load, f)                       # compile
            m = measure(() -> Base.invokelatest(RData.load, f))
            check(m.value isa AbstractDict && !isempty(m.value), "RData.load returned nothing")
            record!(w, m; variant = "J", component = "O2", subcomponent = "RData.jl load " * basename(f),
                    workload = "R ensemble .RData", notes = "file $(filesize(f)) bytes")
        end
    end
end
