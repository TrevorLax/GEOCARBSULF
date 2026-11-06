@testset "fluxes and mass balance" begin
    p, f0 = default_inputs()
    n = length(f0.age)
    d = Dict{Symbol,Vector{Float64}}(nm => copy(getfield(f0, nm)) for nm in TIME_FORCING_NAMES)
    for nm in (:fA, :fR, :fD, :fL, :fSR, :fC)
        d[nm] = fill(1.0, n)
    end
    f1 = TimeForcings(f0.age, d)
    s = G.initial_state(Float64, p)

    # isotopic mass balance of the initial state (f90:291-292)
    @test p.dlst * p.ST ≈ p.dlpy_570 * p.Spy_570 + p.dlsy_570 * p.Ssy_570 + p.dlpa_570 * p.Spa + s.dlsa * p.Ssa
    @test p.dlct * p.CT ≈ p.dlgy_570 * p.Gy_570 + p.dlcy_570 * p.Cy_570 + p.dlga_570 * p.Ga + s.dlca * p.Ca_570

    # with all forcings and plant factors at 1, old-reservoir fluxes equal their *_0 values
    src = G.source_fluxes(n, s, 1.0, 1.0, p, f1)
    @test src.Fwpa == p.Fwpa_0 && src.Fwsa == p.Fwsa_0 && src.Fwga == p.Fwga_0 && src.Fwca == p.Fwca_0
    @test src.Fmp == p.Fmp_0 && src.Fms == p.Fms_0 && src.Fmg == p.Fmg_0 && src.Fmc == p.Fmc_0
    @test src.Fwpy == p.kwpy * p.Spy_570
    @test src.Fyoc == src.Fwca + src.Fmc

    capd34S, capd13C = G.isotope_fractionations(38.0, p)   # present-day O2 mass
    @test capd34S == p.CAPd34S_0 && capd13C == p.CAPd13C_0
    bur = G.burial_fluxes(n, s, src, capd34S, capd13C, f1)
    @test bur.Fbs + bur.Fbp ≈ src.Fwpy + src.Fwpa + src.Fwsy + src.Fwsa + src.Fms + src.Fmp
    @test bur.Fbc + bur.Fbg ≈ src.Fwgy + src.Fwga + src.Fwcy + src.Fwca + src.Fmc + src.Fmg

    @test G.volcanic_weathering_factor(p.Xvolc_0, p) == 1.0
    @test G.update_oxygen(570.0, 25.0, src, bur, 10.0) == 25.0          # first step unchanged
    ox = G.update_oxygen(560.0, 25.0, src, bur, 10.0)
    @test ox ≈ 25 + (bur.Fbg + 15 / 8 * bur.Fbp) * 10 - (src.Fwgy + src.Fwga + src.Fmg) * 10 -
               15 / 8 * (src.Fwpy + src.Fwpa + src.Fmp) * 10
end
