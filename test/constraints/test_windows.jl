@testset "CO2 windows" begin
    age = collect(570.0:-10.0:0.0)
    # two proxies in the 100 Ma bin, one in the 200 Ma bin, none elsewhere
    d = G.ProxyData(
        [99.0, 104.9, 200.0],
        [1000.0, 500.0, 300.0],
        [500.0, 250.0, 150.0],
        [2000.0, 600.0, 600.0],
        [:boron, :boron, :stomata],
        ["", "", ""],
    )
    w = co2_windows(d, age)
    i100 = findfirst(==(100.0), age)
    i200 = findfirst(==(200.0), age)
    # 1000 ± log10(2), 500 ± log10(1.2): envelope [500/1.2, 1000*2]
    @test w.low[i100] ≈ 500 / 1.2
    @test w.high[i100] ≈ 2000
    @test w.low[i200] ≈ 150 && w.high[i200] ≈ 600
    others = setdiff(1:58, [i100, i200])
    @test all(w.low[others] .== 0) && all(w.high[others] .== 50_000)
    w2 = co2_windows(d, age; nsig=2.0)
    @test w2.high[i100] ≈ 4000
    @test co2_windows(d, age; bounds=(0.0, 1500.0)).high[i100] == 1500
    # the real data: every window is non-empty
    real = co2_windows(read_proxy_data(PROXY_FILE), age)
    @test all(real.low .< real.high)
end

@testset "temperature windows" begin
    td = read_temperature_data(TEMP_FILE)
    age = collect(570.0:-10.0:0.0)
    w = temperature_windows(td, age)
    j0 = findfirst(==(0.0), td.time)
    @test w.low[end] ≈ td.T_min[j0] && w.high[end] ≈ td.T_max[j0]
    j = findfirst(==(-100.0), td.time)
    i = findfirst(==(100.0), age)
    @test w.low[i] == td.T_avg[j] - (td.T_avg[j] - td.T_min[j])   # R expression, nsig = 1
    @test all(w.low .<= w.high)
    @test_throws ArgumentError temperature_windows(td, [1000.5])
    @test G.shift(w, fill(1.0, 58)).low == w.low .+ 1
end

@testset "windows and proxy rows must not be inverted (J-24)" begin
    @test_throws ArgumentError Windows([10.0, 0.0], [1.0, 5.0], [2.0, 4.0])
    @test_throws ArgumentError Windows([10.0, 0.0], [1.0, NaN], [2.0, 4.0])
    @test Windows([10.0, 0.0], [1.0, 4.0], [2.0, 4.0]) isa Windows          # low == high is allowed
    hdr = "age,co2,co2_low,co2_high,proxy_type,reference\n"
    @test_throws ArgumentError read_proxy_data(tmpfile(hdr * "100,1000,500,800,boron,x\n"); proxies=(:boron,))
    @test_throws ArgumentError read_proxy_data(tmpfile(hdr * "100,1000,1200,2000,boron,x\n"); proxies=(:boron,))
    ok = read_proxy_data(tmpfile(hdr * "100,1000,,2000,boron,x\n"); proxies=(:boron,))   # co2_low may be missing
    @test length(ok) == 1 && isnan(ok.co2_low[1])
    # an inverted row of a proxy type that is not used does not matter
    @test length(read_proxy_data(tmpfile(hdr * "100,1000,500,800,stomata,x\n200,300,150,600,boron,y\n"); proxies=(:boron,))) == 1
end
