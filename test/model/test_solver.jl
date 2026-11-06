@testset "CO2 solver" begin
    p, f = default_inputs()
    o = ModelOptions(iteration_threshold = 50)
    k = G.resolve_constants(o)

    # vascular regime: manufactured problem with known root R* = 2
    t = 100.0
    i = findfirst(==(t), f.age)
    gcm = G.gcm_factor(t, p, o, k)
    fw, = G._vascular_terms(2.0, t, f.RT[i], f.GEOG[i], gcm, p)
    R, st, it = G.solve_rco2(t, 3.0, fw, gcm, f.RT[i], f.GEOG[i], p, o, k)
    @test st == Converged
    @test isapprox(R, 2.0; rtol = 0.02)
    @test it >= 1

    # non-vascular regime with the exact derivative (finding F-01 option)
    t2 = 450.0
    i2 = findfirst(==(t2), f.age)
    oc = ModelOptions(iteration_threshold = 50, corrected_newton_derivative = true)
    gcm2 = G.gcm_factor(t2, p, oc, k)
    fw2, = G._nonvascular_terms(5.0, t2, f.RT[i2], f.GEOG[i2], gcm2, p, true, true)
    R2, st2, _ = G.solve_rco2(t2, 8.0, fw2, gcm2, f.RT[i2], f.GEOG[i2], p, oc, k)
    @test st2 == Converged
    @test isapprox(R2, 5.0; rtol = 0.02)

    # with exp_fnBb = 0.5 the Fortran derivative is the exact one
    @test p.exp_fnBb == 0.5
    R3, _, _ = G.solve_rco2(t2, 8.0, fw2, gcm2, f.RT[i2], f.GEOG[i2], p, o, k)
    @test isapprox(R3, R2; rtol = 1e-10)

    # failure modes are reported, never thrown
    o1 = ModelOptions(iteration_threshold = 1)
    _, st4, it4 = G.solve_rco2(t, 3.0, fw, gcm, f.RT[i], f.GEOG[i], p, o1, G.resolve_constants(o1))
    @test st4 == NotConverged && it4 == 1
    _, st5, _ = G.solve_rco2(t, 3.0, fw, gcm, f.RT[i], -1e6, p, o, k)     # negative power base
    @test st5 == NaNEncountered
    _, st6, _ = G.solve_rco2(365.0, 3.0, fw, gcm, f.RT[i], -1e6, p, o, k)  # blended regime
    @test st6 == NaNEncountered
end
