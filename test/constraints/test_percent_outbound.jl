@testset "percent outbound" begin
    w = Windows(1:4, fill(0.0, 4), fill(1.0, 4))
    @test legacy_percent_outbound([0.5, 0.5, 0.5, 0.5], w) == 0
    @test legacy_percent_outbound([0.5, 2.0, -1.0, 0.5], w) == 0.5
    @test legacy_percent_outbound([0.0, 1.0, 0.5, 0.5], w) == 0          # bounds are inside
    @test legacy_percent_outbound([0.5, Inf, 0.5, 0.5], w) == 1          # failed Fortran step
    @test legacy_percent_outbound([NaN, Inf, 0.5, 0.5], w) == 1          # Inf wins (R checks it first)
    @test isnan(legacy_percent_outbound([NaN, 0.5, 0.5, 0.5], w))        # R: NA
    @test_throws ArgumentError legacy_percent_outbound([0.5], w)

    # on model results: temperatures are compared as temp + T0, failures optionally rejected
    p, f = default_inputs()
    r = run_geocarb(p, f)
    tw = temperature_windows(read_temperature_data(TEMP_FILE), f.age)
    cw = co2_windows(read_proxy_data(PROXY_FILE), f.age)
    @test percent_outbound(r, tw, :temp) == legacy_percent_outbound(r.temp .+ 15, tw)
    @test percent_outbound(r, cw, :co2) == legacy_percent_outbound(r.co2, cw)
    @test_throws ArgumentError percent_outbound(r, cw, :o2)
    bad = GeocarbResult(r.age, copy(r.co2), copy(r.o2), copy(r.temp), copy(r.status), copy(r.iterations))
    bad.status[10] = NotConverged
    @test percent_outbound(bad, tw, :temp; reject_failed=true) == 1      # finding F-04 fix
    @test percent_outbound(bad, tw, :temp) == percent_outbound(r, tw, :temp)
end
