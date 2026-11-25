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
    @test size(acf_quantiles(res; lag_max=5)) == (6, 9, 12)
    sc = survival_curve([0.3, 0.1, 0.2])
    @test sc.x == [0.1, 0.2, 0.3] && sc.survival ≈ [0.75, 0.5, 0.25]
end
