@testset "run_geocarb" begin
    p, f = default_inputs()
    r = run_geocarb(p, f)
    @test r isa GeocarbResult{Float64}
    @test length(r.co2) == length(r.o2) == length(r.temp) == length(r.status) == 58
    @test r.age == f.age
    @test temperature(r) == r.temp .+ 15
    @test temperature(r; geog=f.GEOG) ≈ r.temp .+ 15 .+ f.GEOG
    @test temperature(r; remove_solar=p.Ws) ≈ r.temp .+ 15 .+ p.Ws .* r.age ./ 570
    # removing the solar term leaves T0 + GCM·ln(RCO2), the CO2-only warming (J-15)
    gcm = [G.gcm_factor(t, p, ModelOptions(), G.resolve_constants(ModelOptions())) for t in r.age]
    @test temperature(r; remove_solar=p.Ws) ≈ 15 .+ gcm .* log.(r.co2 ./ 250)
    @test (@test_deprecated temperature(r; Ws=p.Ws)) == temperature(r; remove_solar=p.Ws)
    @test_throws ArgumentError temperature(r; Ws=p.Ws, remove_solar=p.Ws)

    @testset "status invariants on 200 prior draws" begin
        ok_fail = ok_conv = ok_nan = ok_present = true
        nconv = 0
        for (pp, ff) in random_inputs(200)
            rr = run_geocarb(pp, ff)
            for i in eachindex(rr.status)
                s = rr.status[i]
                if G.isfailure(s)
                    ok_fail &= rr.co2[i] == Inf && rr.o2[i] == Inf
                elseif s == Converged
                    ok_conv &= isfinite(rr.co2[i]) && isfinite(rr.temp[i])
                    nconv += 1
                else
                    ok_nan &= isnan(rr.co2[i])
                end
                s == PresentDayCheckFailed && (ok_present &= rr.age[i] == 0)
            end
        end
        @test ok_fail      # failed steps: CO2 and O2 are Inf (Fortran convention)
        @test ok_conv      # converged steps: finite CO2 and temperature
        @test ok_nan       # InvalidState: NaN outputs
        @test ok_present   # the present-day check only applies at t = 0
        @test nconv > 0
    end

    @testset "supplemental options" begin
        ctrl = ModelOptions(; gym_angio_transition=(130.0, 80.0), gym_factor=1.0, dT2X_ramp=false)
        for (pp, ff) in random_inputs(50; seed=99)
            a = run_geocarb(pp, ff)
            b = run_geocarb(pp, ff; options=ctrl)
            @test isequal(a.co2, b.co2) && isequal(a.o2, b.o2) && isequal(a.temp, b.temp)
        end
        ramp = run_geocarb(p, f; options=ModelOptions(; dT2X_ramp=true))
        @test !isequal(ramp.temp, r.temp)
        @test isequal(ramp.temp[1:43], r.temp[1:43])      # identical before 140 Ma
    end

    @testset "input validation" begin
        # the grid must run from 570 Ma to the present (J-20)
        dd(a) = Dict{Symbol,Vector{Float64}}(n => fill(1.0, length(a)) for n in TIME_FORCING_NAMES)
        @test_throws ArgumentError run_geocarb(p, TimeForcings(collect(570.0:-10.0:10.0), dd(570.0:-10.0:10.0)))
        @test_throws ArgumentError run_geocarb(p, TimeForcings(collect(560.0:-10.0:0.0), dd(560.0:-10.0:0.0)))
        age5 = collect(570.0:-5.0:0.0)
        d = Dict{Symbol,Vector{Float64}}(n => fill(1.0, length(age5)) for n in TIME_FORCING_NAMES)
        f5 = TimeForcings(age5, d)
        @test_throws ArgumentError run_geocarb(p, f5)          # spacing ≠ dt
        @test run_geocarb(p, f5; options=ModelOptions(; dt=5.0)) isa GeocarbResult
        @test_throws ArgumentError run_geocarb!(GeocarbResult{Float64}(1:3), p, f)
        # the output must be on the forcings' age grid, not just of the same length (J-25)
        @test_throws ArgumentError run_geocarb!(GeocarbResult{Float64}(f.age .- 0.5), p, f)
        # a spacing equal to dt up to rounding is accepted (J-06)
        fr = TimeForcings(collect(range(570.0, 0.0; length=58)), Dict(n => getfield(f, n) for n in TIME_FORCING_NAMES))
        @test isequal(run_geocarb(p, fr).co2, run_geocarb(p, f).co2)
    end

    @testset "no allocations in run_geocarb!" begin
        out = GeocarbResult{Float64}(f.age)
        measure(out, p, f) = @allocated run_geocarb!(out, p, f)
        measure(out, p, f)
        @test measure(out, p, f) == 0
    end

    @testset "generic number types" begin
        p32 = ConstantParams{Float32}(Float32.(parameter_vector(p))...)
        f32 = TimeForcings(
            f.age, Dict{Symbol,Vector{Float32}}(n => Float32.(getfield(f, n)) for n in TIME_FORCING_NAMES)
        )
        r32 = run_geocarb(p32, f32)
        @test r32 isa GeocarbResult{Float32}
        @test succeeded(r32) && isapprox(r32.co2, run_geocarb(p, f).co2; rtol=1e-3)
        # derivatives through the whole run (including the CO2 solve) agree with finite differences (J-08)
        h(x) = run_geocarb(update(p; deltaT2X=x), f).temp[end - 1]
        g = ForwardDiff.derivative(h, p.deltaT2X)
        fd = (h(p.deltaT2X + 1e-5) - h(p.deltaT2X - 1e-5)) / 2e-5
        @test g isa Float64 && isapprox(g, fd; rtol=1e-5)
        names = collect(CONSTANT_PARAMETER_NAMES)
        grad = ForwardDiff.gradient(v -> run_geocarb(ConstantParams(names, v), f).co2[30], parameter_vector(p))
        @test all(isfinite, grad) && length(grad) == 56
    end
end
