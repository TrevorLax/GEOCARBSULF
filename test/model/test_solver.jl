@testset "CO2 solver" begin
    p, f = default_inputs()
    o = ModelOptions(; iteration_threshold=50)
    k = G.resolve_constants(o)

    # vascular regime: manufactured problem with known root R* = 2
    t = 100.0
    i = findfirst(==(t), f.age)
    gcm = G.gcm_factor(t, p, o, k)
    fw, = G._vascular_terms(2.0, t, f.RT[i], f.GEOG[i], gcm, p)
    R, st, it = G.solve_rco2(t, 3.0, fw, gcm, f.RT[i], f.GEOG[i], p, o, k)
    @test st == Converged
    @test isapprox(R, 2.0; rtol=0.02)
    @test it >= 1

    # non-vascular regime with the exact derivative (finding F-01 option)
    t2 = 450.0
    i2 = findfirst(==(t2), f.age)
    oc = ModelOptions(; iteration_threshold=50, corrected_newton_derivative=true)
    gcm2 = G.gcm_factor(t2, p, oc, k)
    fw2, = G._nonvascular_terms(5.0, t2, f.RT[i2], f.GEOG[i2], gcm2, p, true, true)
    R2, st2, _ = G.solve_rco2(t2, 8.0, fw2, gcm2, f.RT[i2], f.GEOG[i2], p, oc, k)
    @test st2 == Converged
    @test isapprox(R2, 5.0; rtol=0.02)

    # with exp_fnBb = 0.5 the Fortran derivative is the exact one
    @test p.exp_fnBb == 0.5
    R3, _, _ = G.solve_rco2(t2, 8.0, fw2, gcm2, f.RT[i2], f.GEOG[i2], p, o, k)
    @test isapprox(R3, R2; rtol=1e-10)

    # failure modes are reported, never thrown
    o1 = ModelOptions(; iteration_threshold=2)                    # one Newton update, then failure
    _, st4, it4 = G.solve_rco2(t, 3.0, fw, gcm, f.RT[i], f.GEOG[i], p, o1, G.resolve_constants(o1))
    @test st4 == NotConverged && it4 == 2
    _, st5, _ = G.solve_rco2(t, 3.0, fw, gcm, f.RT[i], -1e6, p, o, k)     # negative power base
    @test st5 == NaNEncountered
    _, st6, _ = G.solve_rco2(365.0, 3.0, fw, gcm, f.RT[i], -1e6, p, o, k)  # blended regime
    @test st6 == NaNEncountered

    # a NaN mass-balance target: RCO2 shrinks every iteration; if the iteration limit
    # comes before the shrinking RCO2 itself produces a NaN, the Fortran reports
    # NotConverged. report_nan_target labels it NaNEncountered; the iteration itself is
    # identical (J-21)
    for tt in (450.0, 365.0, 100.0)
        o3 = ModelOptions(; iteration_threshold=3)
        R7, st7, it7 = G.solve_rco2(tt, 3.0, NaN, gcm, f.RT[i], f.GEOG[i], p, o3, G.resolve_constants(o3))
        on = ModelOptions(; iteration_threshold=3, report_nan_target=true)
        R8, st8, it8 = G.solve_rco2(tt, 3.0, NaN, gcm, f.RT[i], f.GEOG[i], p, on, G.resolve_constants(on))
        @test st7 == NotConverged && st8 == NaNEncountered
        @test R7 === R8 && it7 == it8
    end

    # blending interval of the solver (J-22): Fortran 381–350 Ma, or 380–350 Ma like fE/fBB
    ou = ModelOptions(; iteration_threshold=50, unified_vascular_blend=true)
    ku = G.resolve_constants(ou)
    t380 = 380.0
    g380 = G.gcm_factor(t380, p, o, k)
    fwo, = G._nonvascular_terms(4.0, t380, f.RT[i], f.GEOG[i], g380, p, false, true)
    Ru, stu, _ = G.solve_rco2(t380, 6.0, fwo, g380, f.RT[i], f.GEOG[i], p, ou, ku)
    @test stu == Converged && isapprox(Ru, 4.0; rtol=0.02)    # purely non-vascular at 380 Ma
    Rl, = G.solve_rco2(t380, 6.0, fwo, g380, f.RT[i], f.GEOG[i], p, o, k)
    @test Rl != Ru                                             # the Fortran blend is 1/31 vascular there
end
