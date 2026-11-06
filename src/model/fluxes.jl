"""
    source_fluxes(i, s, fE, fBB, p, f) -> NamedTuple

Weathering and degassing fluxes at time step `i` (10^18 mol/Myr; f90:363-378; see
Berner 2006a pp. 5660-5661 for the `Fwp`, `Fws` and `Fwg` fluxes).
Returned fields: `Fwpy, Fwsy, Fwgy, Fwcy` (young pyrite, CaSO4, organic C, carbonate C),
`Fwpa, Fwsa, Fwga, Fwca` (old reservoirs), `Fmp, Fms, Fmg, Fmc` (degassing) and
`Fyop, Fyos, Fyog, Fyoc` (degassing + old-reservoir weathering).
"""
@inline function source_fluxes(i::Int, s::ReservoirState, fE, fBB, p::ConstantParams, f::TimeForcings)
    fA = f.fA[i]; fR = f.fR[i]; fD = f.fD[i]; fL = f.fL[i]; fSR = f.fSR[i]; fC = f.fC[i]
    Fwpy = fA * fR * p.kwpy * s.Spy
    Fwsy = fA * fD * p.kwsy * s.Ssy
    Fwgy = fA * fR * p.kwgy * s.Gy
    Fwcy = fA * fD * fL * fE * fBB * p.kwcy * s.Cy
    Fwpa = fR * p.Fwpa_0
    Fwsa = fA * fD * p.Fwsa_0
    Fwga = fR * p.Fwga_0
    Fwca = fA * fD * fL * fE * fBB * p.Fwca_0
    Fmp = fSR * p.Fmp_0
    Fms = fSR * p.Fms_0
    Fmg = fSR * p.Fmg_0
    Fmc = fSR * fC * p.Fmc_0
    Fyop = Fwpa + Fmp
    Fyos = Fwsa + Fms
    Fyog = Fwga + Fmg
    Fyoc = Fwca + Fmc
    return (; Fwpy, Fwsy, Fwgy, Fwcy, Fwpa, Fwsa, Fwga, Fwca, Fmp, Fms, Fmg, Fmc, Fyop, Fyos, Fyog, Fyoc)
end

"""
    isotope_fractionations(oxygen, p) -> (CAPd34S, CAPd13C)

Isotopic fractionations between sulfate and pyrite sulfur, and between carbonate and
organic carbon, as functions of the O2 mass (Berner 2006a; f90:381-382).
"""
@inline function isotope_fractionations(oxygen, p::ConstantParams)
    capd34S = p.CAPd34S_0 * nanpow(oxygen / O2_MASS_PRESENT, p.n)
    capd13C = p.CAPd13C_0 + p.J * (oxygen / O2_MASS_PRESENT - 1)
    return capd34S, capd13C
end

"""
    burial_fluxes(i, s, src, capd34S, capd13C, f) -> NamedTuple

Burial fluxes of pyrite (`Fbp`), organic carbon (`Fbg`), CaSO4 sulfur (`Fbs`) and
carbonate carbon (`Fbc`) from isotopic mass balance (f90:383-390).
"""
@inline function burial_fluxes(i::Int, s::ReservoirState, src, capd34S, capd13C, f::TimeForcings)
    d34S = f.d34S[i]; d13C = f.d13C[i]
    Fbp = (1 / capd34S) * ((d34S - s.dlsy) * src.Fwsy + (d34S - s.dlsa) * src.Fwsa +
                           (d34S - s.dlpy) * src.Fwpy + (d34S - s.dlpa) * src.Fwpa +
                           (d34S - s.dlsa) * src.Fms + (d34S - s.dlpa) * src.Fmp)
    Fbg = (1 / capd13C) * ((d13C - s.dlcy) * src.Fwcy + (d13C - s.dlca) * src.Fwca +
                           (d13C - s.dlgy) * src.Fwgy + (d13C - s.dlga) * src.Fwga +
                           (d13C - s.dlca) * src.Fmc + (d13C - s.dlga) * src.Fmg)
    Fbs = src.Fwpy + src.Fwpa + src.Fwsy + src.Fwsa + src.Fms + src.Fmp - Fbp
    Fbc = src.Fwgy + src.Fwga + src.Fwcy + src.Fwca + src.Fmc + src.Fmg - Fbg
    return (; Fbp, Fbg, Fbs, Fbc)
end

"""
    update_oxygen(t, oxygen, src, bur, dt) -> oxygen

Atmospheric O2 mass for this step (f90:403-405). The first step (t = 570) keeps the
initial value.
"""
@inline function update_oxygen(t::Real, oxygen, src, bur, dt)
    if t < AGE_MAX
        return oxygen + (bur.Fbg + PYRITE_O2_RATIO * bur.Fbp) * dt - (src.Fwgy + src.Fwga + src.Fmg) * dt -
               PYRITE_O2_RATIO * (src.Fwpy + src.Fwpa + src.Fmp) * dt
    end
    return oxygen
end

"""
    silicate_weathering_no_climate(i, src, bur, fE, fvolc, p, f) -> fwsi_no_climate

Silicate weathering at time `t` relative to the present without climatic effects:
the silicate weathering required by mass balance (burial − carbonate weathering)
divided by the non-climatic factors times `Fwsi_0` (Berner 2004 eq. 5.2; "fB" in the
BASIC code; f90:416).
"""
@inline function silicate_weathering_no_climate(i::Int, src, bur, fE, fvolc, p::ConstantParams, f::TimeForcings)
    return (bur.Fbc - src.Fwcy - src.Fwca) /
           (nanpow(f.fAw_fA[i] * f.fA[i] * f.fD[i], p.exp_fD) * fE * f.fR[i] * fvolc * p.Fwsi_0)
end
