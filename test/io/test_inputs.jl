@testset "prior table" begin
    t = PRIOR_TABLE
    @test count(s -> s.kind == :constant, t.specs) == 56
    @test count(s -> s.kind == :time_array, t.specs) == 12
    s = G.spec(t, :deltaT2X)
    @test s.distribution == :lognormal && s.mean == 3 && s.two_sigma == 2.5 && s.lower == 1.5 && s.upper == Inf
    @test G.spec(t, :Ws).lower == -Inf                  # "_inf" in the file
    @test G.spec(t, :FERT).upper == 1.0
    @test G.spec(t, :oxygen_570).upper == 143.0
    @test all(s -> s.calibrate, G.constant_specs(t))
    p = mean_constants(t)
    @test p.Fwsi_0 == 6.67 && p.kwcy == 0.018

    # rows in another order give the same table (lookup is by name)
    lines = readlines(PRIOR_FILE)
    shuffled = vcat(lines[1], reverse(lines[2:end]))
    t2 = read_prior_table(tmpfile(join(shuffled, "\n")))
    @test mean_constants(t2) == p
    # a missing parameter is reported
    @test_throws ArgumentError read_prior_table(tmpfile(join(filter(l -> !startswith(l, "GLAC,"), lines), "\n")))
    # a bad distribution type is reported
    bad = replace(join(lines, "\n"), "ACT,constant,TRUE,gaussian" => "ACT,constant,TRUE,cauchy")
    @test_throws ArgumentError read_prior_table(tmpfile(bad))
end

@testset "time arrays" begin
    c = TIME_PRIOR.center
    s = TIME_PRIOR.sigma
    @test c.age == collect(570.0:-10.0:0.0)
    @test c.fAw_fA[end] == 1.0                           # normalised to the present
    raw = read_csv_table(ARRAY_FILE)
    @test c.fAw_fA == G.numeric_column(raw, "fAw_fA_Godderis") ./ G.numeric_column(raw, "fAw_fA_Godderis")[end]
    @test s.fAw_fA == G.numeric_column(raw, "efAw_fA_Godderis")   # σ is not rescaled (as in R)
    @test c.GEOG == G.numeric_column(raw, "GEOG_Godderis")
    @test c.Sr == G.numeric_column(raw, "Sr")
    nog = read_time_arrays(ARRAY_FILE; use_godderis = false)
    @test nog.center.fA == G.numeric_column(raw, "fA")
end

@testset "proxy and temperature data" begin
    d = read_proxy_data(PROXY_FILE)
    @test length(d) == 1213
    @test d.proxy_type[1] == :paleosols                 # grouped by proxy type (getData.R)
    @test count(==(:boron), d.proxy_type) == 224
    @test all(d.co2 .> 0)
    only_boron = read_proxy_data(PROXY_FILE; proxies = (:boron,))
    @test length(only_boron) == 224
    idx = G.proxy_step_index(d, collect(570.0:-10.0:0.0))
    @test all(i -> i === nothing || 1 <= i <= 58, idx)
    j = findfirst(==(196.1), d.age)
    @test idx[j] == findfirst(==(200.0), 570.0:-10.0:0.0)   # 195 ≤ 196.1 < 205

    td = read_temperature_data(TEMP_FILE)
    @test td.time[1] == 0 && td.time[end] == -750
    @test td.T_avg[1] ≈ 14.27553028
    pr = read_park_royer_2011(datapath("ParkRoyer2011_Fig3_85varred.csv"))   # CR-only line endings
    @test length(pr.deltaT2X) > 10 && pr.cdf[end] == 1
end
