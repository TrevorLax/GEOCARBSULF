@testset "precalibration engine" begin
    cfg = small_config()                       # 60 samples in 3 chunks, accept everything scored
    res = run_precalibration(cfg; max_parallel=1, verbose=false)
    n = n_accepted(res)
    @test res.n_simulated == 60
    @test 0 < n <= 60
    @test size(res.constants) == (n, 56)
    @test size(res.time_series) == (58, n, 12)
    @test size(res.co2) == size(res.temp) == size(res.status) == (58, n)
    @test length(res.prcout_co2) == length(res.prcout_temp) == n
    @test all(0 .<= res.prcout_co2 .<= 1) && all(0 .<= res.prcout_temp .<= 1)
    @test all(1 .<= res.sample_keys[:, 1] .<= 3)

    # stored samples reproduce their stored model output
    k = 1
    r = run_geocarb(G.sample_constants_params(res, k), G.sample_forcings(res, k))
    @test isequal(r.co2, res.co2[:, k]) && isequal(r.temp, res.temp[:, k])

    # results do not depend on the number of parallel chunks
    res3 = run_precalibration(cfg; max_parallel=3, verbose=false)
    @test res3.constants == res.constants && isequal(res3.co2, res.co2) && res3.sample_keys == res.sample_keys

    # stopping rule: exactly n_accept_min samples are kept
    few = run_precalibration(with_overrides(cfg; n_accept_min=5); max_parallel=1, verbose=false)
    @test n_accepted(few) == 5 && few.n_simulated == 20
    @test few.constants == res.constants[1:5, :]

    # a single chunk works (a stub in the R code, finding F-12)
    one = run_precalibration(with_overrides(cfg; n_sample=15, n_per_chunk=100); verbose=false)
    @test one.n_simulated == 15

    # strict thresholds can accept nothing without failing
    none = run_precalibration(with_overrides(cfg; threshold=1e-9); verbose=false)
    @test n_accepted(none) == 0 && size(none.time_series) == (58, 0, 12)

    # other samplers, designs and options run (smoke tests; the Cretaceous run usually
    # accepts nothing with 20 draws, so its rule is tested directly below)
    for kw in (
        (time_sampler=:multivariate_t,),
        (constant_design=:global_lhs,),
        (save_covariances=true,),
        (cretaceous_age=90.0, run_on_time_centers=true),
        (model=ModelOptions(; dT2X_ramp=true),),
    )
        rr = run_precalibration(with_overrides(cfg; n_sample=20, n_per_chunk=10, kw...); verbose=false)
        @test rr.n_simulated == 20
        if haskey(kw, :save_covariances)
            @test size(rr.covariances) == (58, 58, n_accepted(rr), 12)
        end
    end

    # reject_failed_runs in the engine: only ~0.6 % of prior draws have no failed step,
    # so draw up to 2000 and stop at the first acceptance
    rf = run_precalibration(
        with_overrides(cfg; reject_failed_runs=true, threshold=0.99, n_sample=2000, n_per_chunk=500, n_accept_min=1);
        verbose=false,
    )
    @test n_accepted(rf) == 1
    @test all(==(UInt8(Converged)), rf.status)

    @testset "acceptance rules on known runs" begin
        p0, f0 = default_inputs()
        r0 = run_geocarb(p0, f0)                 # prior means: every step valid
        @test succeeded(r0)
        copyres(r) = GeocarbResult(r.age, copy(r.co2), copy(r.o2), copy(r.temp), copy(r.status), copy(r.iterations))
        n0 = length(f0.age)
        wide = Windows(f0.age, fill(-1e6, n0), fill(1e6, n0))
        ctx_wide = EvaluationContext(wide, wide)
        bad = copyres(r0)
        bad.status[10] = NotConverged            # a failed step; temperatures unchanged
        @test accepts(OutboundRule(:temp, 0.5; reject_failed=true), r0, ctx_wide)
        @test !accepts(OutboundRule(:temp, 0.5; reject_failed=true), bad, ctx_wide)
        @test accepts(OutboundRule(:temp, 0.5), bad, ctx_wide)          # legacy semantics (finding F-04)
        @test accepts(AllOf(), r0, ctx_wide)

        tw = temperature_windows(read_temperature_data(TEMP_FILE), f0.age)
        ctx = EvaluationContext(wide, tw)
        i90 = findfirst(==(90.0), f0.age)
        inside = copyres(r0)
        inside.temp[i90] = (tw.low[i90] + tw.high[i90]) / 2 - 15
        above = copyres(r0)
        above.temp[i90] = tw.high[i90] + 1 - 15
        below = copyres(r0)
        below.temp[i90] = tw.low[i90] - 1 - 15
        nanr = copyres(r0)
        nanr.temp[i90] = NaN
        rule = CretaceousWindowRule(90.0)
        @test accepts(rule, inside, ctx)
        @test !accepts(rule, above, ctx) && !accepts(rule, below, ctx) && !accepts(rule, nanr, ctx)
        @test_throws ArgumentError accepts(CretaceousWindowRule(95.0), r0, ctx)
        cret = build_rule(with_overrides(cfg; cretaceous_age=90.0, threshold=1.0))
        @test accepts(cret, inside, ctx) && !accepts(cret, above, ctx)
    end

    # save → load round trip, CSV summaries
    dir = mktempdir()
    path = save_result(joinpath(dir, "result.jld2"), res)
    back = load_result(path)
    @test back.constants == res.constants && isequal(back.co2, res.co2) && back.time_series == res.time_series
    @test back.tag == res.tag && back.n_simulated == res.n_simulated && back.provenance == res.provenance
    files = write_summary_csvs(dir, res)
    @test all(isfile, files)
    @test size(read_csv_table(joinpath(dir, "constants.csv")).rows, 1) == n

    # checkpoint / resume gives the same result
    ck = mktempdir()
    a = run_precalibration(cfg; checkpoint_dir=ck, verbose=false)
    @test length(filter(endswith(".jld2"), readdir(ck))) == 3
    b = run_precalibration(cfg; checkpoint_dir=ck, verbose=false)
    @test a.constants == b.constants == res.constants

    # time_center_from: centres from a previous result
    c2 = with_overrides(cfg; time_center_from=path, n_sample=10, n_per_chunk=10)
    setup = G.prepare_precalibration(c2)
    @test setup.center.Sr ≈ vec(Statistics.mean(res.time_series[:, :, 1]; dims=2))

    # merging results
    m = merge_results([res, few])
    @test n_accepted(m) == n + 5 && m.n_simulated == 80
end
