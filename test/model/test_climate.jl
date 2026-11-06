@testset "gcm_factor" begin
    p, _ = default_inputs()
    o = ModelOptions()
    k = G.resolve_constants(o)
    ln2 = k.ln2                       # log(2) as the model uses it (single precision by default)
    @test ln2 == Float64(Float32(log(2.0)))
    @test G.resolve_constants(ModelOptions(fortran_single_literals = false)).ln2 == log(2.0)
    for t in (330.0, 300.0, 260.0, 40.0, 0.0)          # glacial intervals are closed
        @test G.gcm_factor(t, p, o, k) == p.GLAC * p.deltaT2X / ln2
    end
    for t in (331.0, 259.0, 41.0, 100.0, 570.0)
        @test G.gcm_factor(t, p, o, k) == p.deltaT2X / ln2
    end
    @test G.in_glacial_interval(330.0, o) && !G.in_glacial_interval(330.5, o)

    r = ModelOptions(dT2X_ramp = true)                   # supplemental ΔT2x ramp, 130 → 40 Ma
    @test G.gcm_factor(131.0, p, r, k) == p.deltaT2X / ln2
    @test G.gcm_factor(130.0, p, r, k) == p.deltaT2X / ln2
    @test G.gcm_factor(85.0, p, r, k) ≈ ((p.GLAC * 45 + 45) / 90) * p.deltaT2X / ln2
    @test G.gcm_factor(41.0, p, r, k) ≈ ((p.GLAC * 89 + 1) / 90) * p.deltaT2X / ln2
    @test G.gcm_factor(40.0, p, r, k) == p.GLAC * p.deltaT2X / ln2   # glacial again
end
