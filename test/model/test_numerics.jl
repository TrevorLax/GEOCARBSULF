@testset "numerics (Fortran-like NaN semantics)" begin
    @test G.nanpow(2.0, 0.5) ≈ sqrt(2.0)
    @test isnan(G.nanpow(-2.0, 0.5))          # Fortran: NaN, Julia's ^ would throw
    @test G.nanpow(-2.0, 2.0) == 4.0          # integer exponents are fine, as in C pow
    @test G.nanpow(0.0, -1.0) == Inf
    @test isnan(G.nanpow(NaN, 0.3))
    @test isnan(G.nanlog(-1.0))
    @test G.nanlog(0.0) == -Inf
    @test G.nanlog(1.0) == 0.0
    @test isnan(G.nanpow(-8.0, 1 / 3))
end
