@testset "vegetation_fE" begin
    p, _ = default_inputs()
    o = ModelOptions()
    fE(t, opt = o) = G.vegetation_fE(t, p, opt)
    @test fE(570.0) == p.LIFE
    @test fE(390.0) == p.LIFE
    @test fE(380.0) ≈ p.LIFE
    @test fE(365.0) ≈ (p.LIFE + p.GYM) / 2
    @test fE(350.0) == p.GYM
    @test fE(200.0) == p.GYM
    @test fE(130.0) ≈ p.GYM
    @test fE(105.0) ≈ (p.GYM + 1) / 2
    @test fE(80.0) == 1
    @test fE(0.0) == 1
    for knot in (380.0, 350.0, 130.0, 80.0)              # piecewise linear and continuous
        @test isapprox(fE(knot + 1e-9), fE(knot); atol = 1e-6)
    end

    m = ModelOptions(gym_angio_transition = (110, 60), gym_factor = 0.25)
    @test fE(120.0, m) == p.GYM
    @test fE(110.0, m) ≈ 0.25 * p.GYM
    @test fE(85.0, m) ≈ (0.25 * p.GYM + 1) / 2
    @test fE(60.0, m) == 1
    @test fE(365.0, m) == fE(365.0)
    z = ModelOptions(gym_factor = 0.0)                   # NaN in the Fortran (F-09), defined here
    @test fE(100.0, z) ≈ 30 / 50
end

@testset "carbonate_fBB" begin
    p, _ = default_inputs()
    @test G.carbonate_fBB(0.0, 1.0, 4.0, 0.0, p) == 1.0
    A = 1 - p.ACTcarb * p.Ws * (400 / 570)
    @test G.carbonate_fBB(400.0, 1.0, 4.0, 0.0, p) ≈ A
    # at 365 Ma the blend weighs the non-vascular and vascular expressions equally
    A365 = 1 + p.ACTcarb * 4.0 * log(2.0) - p.ACTcarb * p.Ws * (365 / 570)
    nonvasc = A365 * 2.0^p.exp_fnBb
    vasc = A365 * (2 * 2.0 / 3.0)^p.FERT
    @test G.carbonate_fBB(365.0, 2.0, 4.0, 0.0, p) ≈ 0.5 * vasc + 0.5 * nonvasc
    @test isnan(G.carbonate_fBB(100.0, -1.0, 4.0, 0.0, p))   # no DomainError
end
