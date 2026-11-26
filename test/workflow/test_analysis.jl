@testset "analysis" begin
    res = run_precalibration(small_config(; n_sample=40, n_per_chunk=20); verbose=false)
    n = n_accepted(res)
    q = parameter_quantiles(res)
    @test q.names[end] == :deltaT2Xglac && size(q.values) == (57, length(DEFAULT_PROBS))
    @test all(q.values[:, 1] .<= q.values[:, end])
    j = findfirst(==(:deltaT2X), q.names)
    @test q.values[j, 5] ≈ Statistics.median(constant_column(res, :deltaT2X))
    @test size(parameter_quantiles(res; n=100).values) == (57, 9)      # with replacement
    @test size(time_series_quantiles(res)) == (58, 9, 12)

    hc = hindcast(res)
    @test size(hc.co2) == (58, n)
    @test hc.temp[:, 1] ≈ res.temp[:, 1] .+ 15 .+ forcing_series(res, :GEOG)[:, 1]
    hc2 = hindcast(res; options=ModelOptions())                         # re-run gives the same
    @test isequal(hc2.co2, hc.co2)
    # the plotted temperature is the accepted quantity, temp + T0 without GEOG (J-13)
    setup = G.prepare_precalibration(small_config(; n_sample=40, n_per_chunk=20))
    acc = accepted_temperature(res)
    @test hindcast(res; include_geog=false).temp == acc
    @test [legacy_percent_outbound(acc[:, k], setup.ctx.temp_windows) for k in 1:n] == res.prcout_temp
    @test accepted_temperature(res; T0=0) == res.temp

    # run_on_time_centers results: the saved series did not drive the model (J-02)
    rc = run_precalibration(small_config(; n_sample=20, n_per_chunk=20, run_on_time_centers=true); verbose=false)
    if n_accepted(rc) > 0
        @test_throws ArgumentError hindcast(rc)                              # would add sampled GEOG
        @test_throws ArgumentError hindcast(rc; include_geog=false, options=ModelOptions())
        @test hindcast(rc; include_geog=false).temp == accepted_temperature(rc)
        ctr = setup.center
        hcc = hindcast(rc; center=ctr)
        @test hcc.temp[:, 1] ≈ rc.temp[:, 1] .+ 15 .+ ctr.GEOG
        @test isequal(hindcast(rc; center=ctr, options=ModelOptions()).co2, hcc.co2)   # re-run on the centres
    end
    # analysis inputs come from the result's own configuration (J-14)
    inp = result_inputs(res)
    @test inp.temp_windows.low == setup.ctx.temp_windows.low && inp.co2_windows.high == setup.ctx.co2_windows.high
    @test inp.T0 == 15.0 && inp.config.seed == res.config["seed"]
    r2 = run_precalibration(small_config(; n_sample=20, n_per_chunk=20, nsig=2.0, T0=14.0); verbose=false)
    inp2 = result_inputs(r2)
    @test inp2.T0 == 14.0 && inp2.temp_windows.high != inp.temp_windows.high
    @test inp2.temp_windows.high == G.prepare_precalibration(small_config(; nsig=2.0)).ctx.temp_windows.high
    with_config(r, c) = G.PrecalibrationResult(
        r.tag,
        r.config_text,
        c,
        r.age,
        r.constant_names,
        r.constants,
        r.forcing_names,
        r.time_series,
        r.co2,
        r.o2,
        r.temp,
        r.status,
        r.prcout_co2,
        r.prcout_temp,
        r.sample_keys,
        r.n_simulated,
        r.n_evaluated,
        r.covariances,
        r.provenance,
    )
    cfg_gone = copy(res.config)
    cfg_gone["proxy_file"] = "/nonexistent/proxies.csv"
    @test_throws ArgumentError result_inputs(with_config(res, cfg_gone))
    # a result moved from another machine: missing inputs are found by name in datapath()
    cfg_moved = copy(res.config)
    pname = basename(res.config["proxy_file"])
    cfg_moved["proxy_file"] = "/scratch/elsewhere/data/" * pname
    cfg_moved["prior_file"] = raw"D:\elsewhere\data\\" * basename(res.config["prior_file"])
    inp_moved = @test_logs (:warn,) (:warn,) result_inputs(with_config(res, cfg_moved))
    @test inp_moved.config.proxy_file == datapath(pname)
    @test inp_moved.config.prior_file == datapath(basename(res.config["prior_file"]))
    @test inp_moved.co2_windows.high == inp.co2_windows.high
    # `center` only applies to run_on_time_centers results; elsewhere it would be ignored
    @test_throws ArgumentError hindcast(res; center=setup.center)
    rq = row_quantiles(hc.co2)
    @test size(rq) == (58, 9)

    s = climate_sensitivity_summary(res)
    @test length(s.deltaT2X) == 3 && 0 <= s.prob_exceed[6.0] <= 1
    tab = prior_posterior_table(PRIOR_TABLE, res)
    @test length(tab.parameter) == 56 && all(tab.prior_lower .< tab.prior_upper)

    x = randn(StableRNG(1), 500)
    @test bw_nrd0(x) ≈
        0.9 *
          min(Statistics.std(x), (Statistics.quantile(x, 0.75) - Statistics.quantile(x, 0.25)) / 1.34) *
          500^(-0.2)
    k = gaussian_kde(x; from=-6, to=6, n=2001)
    @test isapprox(sum(k.density) * (k.x[2] - k.x[1]), 1; atol=1e-3)
    li = linear_interpolator([0.0, 1.0, 2.0], [0.0, 10.0, 0.0])
    @test li(0.5) == 5.0 && li(2.0) == 0.0 && isnan(li(3.0))

    cs = correlation_screen(res, constant_column(res, :deltaT2X))
    @test cs.names[1] == :deltaT2X && cs.r[1] ≈ 1
    # a parameter without variance (fixed in the prior file) is ranked last, not first (J-18)
    fixed = copy(res.constants)
    jfix = findfirst(==(:GYM), res.constant_names)
    fixed[:, jfix] .= 0.5
    res_fixed = G.PrecalibrationResult(
        res.tag,
        res.config_text,
        res.config,
        res.age,
        res.constant_names,
        fixed,
        res.forcing_names,
        res.time_series,
        res.co2,
        res.o2,
        res.temp,
        res.status,
        res.prcout_co2,
        res.prcout_temp,
        res.sample_keys,
        res.n_simulated,
        res.n_evaluated,
        res.covariances,
        res.provenance,
    )
    for method in (:spearman, :pearson)
        csf = correlation_screen(res_fixed, constant_column(res, :deltaT2X); method=method)
        @test csf.names[1] == :deltaT2X
        @test csf.names[end] == :GYM && isnan(csf.r[end]) && !any(isnan, csf.r[1:(end - 1)])
    end
    @test size(acf_quantiles(res; lag_max=5)) == (6, 9, 12)
    sc = survival_curve([0.3, 0.1, 0.2])
    @test sc.x == [0.1, 0.2, 0.3] && sc.survival ≈ [0.75, 0.5, 0.25]
end
