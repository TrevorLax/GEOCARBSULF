# The Julia counterpart of the sections of analysis_and_plots.R that the timing benchmark
# measures (plan §3.7–3.8). Used by julia/bench_analysis.jl (A/G on the shared ensemble)
# and julia/pipeline_x1.jl (end to end). Section names match the timers of the generated
# analysis_and_plots_timed.R, so collect.jl can put both side by side.
#
# Not ported because the R analysis does it differently or not at all:
#   * deltaT2X_samplesize.pdf and co2_and_uncertainties.pdf have no Makie function yet
#     (R-only rows in the report);
#   * the supplemental and Cretaceous parts of analysis_and_plots.R are excluded on both sides.

using Statistics: Statistics, mean, cor
using StatsBase: corspearman
using GeocarbPrecalibration: StableRNG, read_park_royer_2011, linear_interpolator, spec

const EXPERIMENT_TAGS = [string(c, "_out", th) for th in (30, 35, 40, 45, 50) for c in ("c", "t", "ct")]

mutable struct SectionTimer
    w::RawWriter
    variant::String
    workload::String
    n::Int
    times::Dict{String,Float64}
end
SectionTimer(w, variant, workload, n) = SectionTimer(w, variant, workload, n, Dict{String,Float64}())

function section(f, st::SectionTimer, name::AbstractString)
    t0 = time_ns()
    v = f()
    st.times[name] = get(st.times, name, 0.0) + (time_ns() - t0) / 1e9
    return v
end

function flush_sections!(st::SectionTimer; component_of=name -> first(split(name)), mode="warm")
    for (name, t) in sort!(collect(st.times))
        comp = first(split(name))
        record!(
            st.w;
            variant=st.variant,
            component=comp,
            subcomponent=name,
            workload=st.workload,
            n=st.n,
            wall_s=t,
            mode=mode,
        )
    end
end

"""
    julia_analysis!(st, load_result_of, num_samples; figdir = nothing, extra_seeds = true)

Run the analysis sections. `load_result_of(tag)` returns a `PrecalibrationResult` (its
cost is section A1). Returns a Dict of numbers used by the correctness guards.
"""
function julia_analysis!(
    st::SectionTimer, load_result_of, num_samples::Integer; figdir=nothing, extra_seeds=true, rng_seed=1
)
    out = Dict{String,Any}()
    table, proxy, tw, cw = section(st, "A0 setup") do
        table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
        proxy = read_proxy_data(datapath("CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv"))
        tp = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
        tw = temperature_windows(read_temperature_data(datapath("Mills_GR_2019_temp_co2.csv")), tp.center.age)
        cw = co2_windows(proxy, tp.center.age)
        (table, proxy, tw, cw)
    end

    # A1 load + A2 parameter and time-series quantiles (the R loop interleaves them)
    results = Dict{String,PrecalibrationResult}()
    pq = Dict{String,Any}()
    tq = Dict{String,Any}()
    for tag in EXPERIMENT_TAGS
        r = section(() -> load_result_of(tag), st, "A1 load")
        if tag == "ct_out30" && extra_seeds
            parts = [
                r,
                section(() -> load_result_of("ct_out30_seed11"), st, "A1 load"),
                section(() -> load_result_of("ct_out30_seed2020"), st, "A1 load"),
            ]
            r = section(() -> merge_results(parts; tag=tag), st, "A2 parameter and time-series quantiles")
        end
        results[tag] = r
        section(st, "A2 parameter and time-series quantiles") do
            pq[tag] = parameter_quantiles(r; n=num_samples, rng=StableRNG(rng_seed))
            tq[tag] = time_series_quantiles(r)
        end
    end
    out["deltaT2X_quantiles_c_out30"] = pq["c_out30"].values[findfirst(==(:deltaT2X), pq["c_out30"].names), :]

    # A3 hindcasts: (a) re-run the model, as the R analysis does; (b) reuse saved outputs
    hc = Dict{String,Any}()
    prc = Dict{String,Any}()
    age = results["ct_out30"].age
    jgeog = findfirst(==(:GEOG), results["ct_out30"].forcing_names)
    section(st, "A3 hindcasts (model re-run)") do
        for tag in EXPERIMENT_TAGS
            r = results[tag]
            h = hindcast(r; options=ModelOptions(), n=num_samples, include_geog=false, rng=StableRNG(rng_seed))
            prc[tag] = hcat(
                [legacy_percent_outbound(view(h.co2, :, k), cw) for k in axes(h.co2, 2)],
                [legacy_percent_outbound(view(h.temp, :, k), tw) for k in axes(h.temp, 2)],
            )
            temp = h.temp .+ r.time_series[:, h.idx, jgeog]
            hc[tag] = (co2=h.co2, temp=temp, idx=h.idx)
        end
    end
    section(st, "A3 hindcasts (reuse saved outputs)") do
        for tag in EXPERIMENT_TAGS
            hindcast(results[tag]; n=num_samples, rng=StableRNG(rng_seed))
        end
    end
    mq = section(st, "A2 hindcast quantiles") do
        Dict(tag => (co2=row_quantiles(hc[tag].co2), temp=row_quantiles(hc[tag].temp)) for tag in EXPERIMENT_TAGS)
    end

    r30 = results["ct_out30"]
    nums = section(st, "A4 KDEs and sensitivity numbers") do
        s = constant_column(r30, :deltaT2X)
        g = constant_column(r30, :GLAC)
        k1 = gaussian_kde(s; from=0, to=10)
        k2 = gaussian_kde(g; from=1, to=5)
        k3 = gaussian_kde(s .* g; from=0, to=25)
        pr = read_park_royer_2011(datapath("ParkRoyer2011_Fig3_85varred.csv"))
        summ = climate_sensitivity_summary(r30)
        fr = Dict(
            tag => (
                count(<(0.25), view(prc[tag], :, 1)) / size(prc[tag], 1),
                count(<(0.25), view(prc[tag], :, 2)) / size(prc[tag], 1),
            ) for tag in ("t_out30", "ct_out30", "c_out30")
        )
        (kde=(k1, k2, k3), park_royer=pr, summary=summ, fractions=fr)
    end

    prior_q = section(st, "A2 prior time-series sampling") do
        tp = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
        sampler = InverseWishartSampler(tp)
        nt = length(tp.center.age)
        series = Array{Float64,3}(undef, nt, num_samples, 12)
        buf = copy(tp.center)
        rng = StableRNG(rng_seed)
        for i in 1:num_samples
            sample_time_forcings!(rng, buf, sampler)
            for (j, nm) in enumerate(TIME_FORCING_NAMES)
                series[:, i, j] .= getfield(buf, nm)
            end
        end
        q = Array{Float64,3}(undef, nt, length(DEFAULT_PROBS), 12)
        for j in 1:12, t in 1:nt
            q[t, :, j] .= Statistics.quantile(view(series, t, :, j), DEFAULT_PROBS)
        end
        q
    end

    out["som_table"] = section(() -> prior_posterior_table(table, r30), st, "A6 prior/posterior table")

    section(st, "A5 correlations and ACFs") do
        r50 = results["c_out50"]
        h = hc["c_out50"]
        rows = [findfirst(==(a), age) for a in 90.0:10.0:140.0]
        target = vec(mean(h.temp[rows, :]; dims=1))
        sub = PrecalibrationResult(
            r50.tag,
            r50.config_text,
            r50.config,
            r50.age,
            r50.constant_names,
            r50.constants[h.idx, :],
            r50.forcing_names,
            r50.time_series[:, h.idx, :],
            r50.co2[:, h.idx],
            r50.o2[:, h.idx],
            r50.temp[:, h.idx],
            r50.status[:, h.idx],
            r50.prcout_co2[h.idx],
            r50.prcout_temp[h.idx],
            r50.sample_keys[h.idx, :],
            r50.n_simulated,
            nothing,
            r50.provenance,
        )
        correlation_screen(sub, target; method=:spearman)
        correlation_screen(sub, target; method=:pearson)
        ts = reshape(permutedims(sub.time_series, (2, 1, 3)), size(sub.time_series, 2), :)
        [corspearman(view(ts, :, j), target) for j in axes(ts, 2)]
        [cor(view(ts, :, j), target) for j in axes(ts, 2)]
        ds = constant_column(r30, :deltaT2X)
        correlation_screen(r30, ds; method=:spearman)
        correlation_screen(r30, ds; method=:pearson)
        ts30 = reshape(permutedims(r30.time_series, (2, 1, 3)), size(r30.time_series, 2), :)
        [corspearman(view(ts30, :, j), ds) for j in axes(ts30, 2)]
        [cor(view(ts30, :, j), ds) for j in axes(ts30, 2)]
        acf_quantiles(r30; lag_max=20)
    end

    if figdir !== nothing
        mkpath(figdir)
        prior = TruncatedPrior(spec(table, :deltaT2X))
        figs = [
            ("G2 model_vs_proxy", "model_vs_proxy.pdf", () -> plot_model_vs_proxy(r30, proxy, tw)),
            (
                "G2 deltaT2X_distributions",
                "deltaT2X_distributions.pdf",
                () -> plot_deltaT2X_distributions(r30; prior=prior, park_royer=nums.park_royer),
            ),
            ("G2 deltaT2X_experiments", "deltaT2X_experiments.pdf", () -> plot_deltaT2X_experiments(results)),
            (
                "G2 time_series_parameters",
                "time_series_parameters.pdf",
                () -> plot_time_series_parameters(r30, prior_q),
            ),
            (
                "G2 time_series_autocorrelations",
                "time_series_autocorrelations.pdf",
                () -> plot_time_series_autocorrelations(r30),
            ),
            (
                "G2 co2_windows_and_proxies",
                "co2_windows_and_proxies.pdf",
                () -> plot_co2_windows_and_proxies(proxy, cw),
            ),
            ("G2 gym_modification", "gym_modification.pdf", () -> plot_gym_modification()),
        ]
        out["figures"] = figs
        out["figdir"] = figdir
    end
    return out
end

"""
    draw_figures!(st, figs, figdir, savefn; mode)

Build and save every figure, timing the two steps separately (G2) and recording the file
size (G3). `savefn(path, fig)` is `CairoMakie.save`.
"""
function draw_figures!(st::SectionTimer, figs, figdir, savefn; mode="warm")
    for (name, file, build) in figs
        t0 = time_ns()
        fig = Base.invokelatest(build)
        t1 = time_ns()
        path = joinpath(figdir, file)
        Base.invokelatest(savefn, path, fig)
        t2 = time_ns()
        record!(
            st.w;
            variant=st.variant,
            component="G2",
            subcomponent="$(name): build",
            workload=st.workload,
            n=st.n,
            wall_s=(t1 - t0) / 1e9,
            mode=mode,
        )
        record!(
            st.w;
            variant=st.variant,
            component="G2",
            subcomponent="$(name): write file",
            workload=st.workload,
            n=st.n,
            wall_s=(t2 - t1) / 1e9,
            mode=mode,
        )
        record!(
            st.w;
            variant=st.variant,
            component="G3",
            subcomponent=name,
            workload=st.workload,
            n=st.n,
            wall_s=NaN,
            alloc_bytes=filesize(path),
            mode=mode,
            notes="file size in alloc_bytes",
        )
    end
end
