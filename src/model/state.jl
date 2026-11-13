"""
    ReservoirState{T}

Masses (10^18 mol), isotopic compositions (per mil) and Sr ratios that are carried from
one time step to the next (f90:279-294 and 529-545). Immutable: every step builds a new
state, which keeps the time loop free of hidden mutation.
"""
struct ReservoirState{T<:Real}
    oxygen::T
    Gy::T
    Cy::T
    Ca::T
    Ssy::T
    Spy::T
    dlsy::T
    dlcy::T
    dlpy::T
    dlpa::T
    dlgy::T
    dlga::T
    dlsa::T
    dlca::T
    Rcy::T
    Rca::T
end

"""
    initial_state(T, p::ConstantParams) -> ReservoirState{T}

State at 570 Ma. `dlsa` and `dlca` follow from isotopic mass balance (f90:291-292).
"""
function initial_state(::Type{T}, p::ConstantParams) where {T<:Real}
    dlsa = (p.dlst * p.ST - (p.dlpy_570 * p.Spy_570 + p.dlsy_570 * p.Ssy_570 + p.dlpa_570 * p.Spa)) / p.Ssa
    dlca = (p.dlct * p.CT - (p.dlgy_570 * p.Gy_570 + p.dlcy_570 * p.Cy_570 + p.dlga_570 * p.Ga)) / p.Ca_570
    return ReservoirState{T}(
        p.oxygen_570,
        p.Gy_570,
        p.Cy_570,
        p.Ca_570,
        p.Ssy_570,
        p.Spy_570,
        p.dlsy_570,
        p.dlcy_570,
        p.dlpy_570,
        p.dlpa_570,
        p.dlgy_570,
        p.dlga_570,
        dlsa,
        dlca,
        p.Rcy_570,
        p.Rca_570,
    )
end

"""
    update_reservoirs(s, oxygen, src, bur, capd34S, capd13C, roc, d34S, d13C, p, dt)

New masses and isotopic values for the next time step (f90:529-545). The updates are
sequential, as in the Fortran: each line uses the values updated on the lines before it.
"""
@inline function update_reservoirs(
    s::ReservoirState{T}, oxygen, src, bur, capd34S, capd13C, roc, d34S, d13C, p::ConstantParams, dt
) where {T}
    Spy = s.Spy + (bur.Fbp - src.Fwpy - src.Fyop) * dt
    Ssy = s.Ssy + (bur.Fbs - src.Fwsy - src.Fyos) * dt
    Gy = s.Gy + (bur.Fbg - src.Fwgy - src.Fyog) * dt
    Cy = s.Cy + (bur.Fbc - src.Fwcy - src.Fyoc) * dt
    Ca = p.CT - Gy - p.Ga - Cy - p.COC

    dlpy = s.dlpy + ((d34S - s.dlpy - capd34S) * bur.Fbp / Spy) * dt
    dlpa = s.dlpa + (src.Fyop * (dlpy - s.dlpa) / p.Spa) * dt
    dlsy = s.dlsy + ((d34S - s.dlsy) * bur.Fbs / Ssy) * dt
    dlsa = s.dlsa + (src.Fyos * (dlsy - s.dlsa) / p.Ssa) * dt
    dlgy = s.dlgy + ((d13C - s.dlgy - capd13C) * bur.Fbg / Gy) * dt
    dlga = s.dlga + (src.Fyog * (dlgy - s.dlga) / p.Ga) * dt
    dlcy = s.dlcy + ((d13C - s.dlcy) * bur.Fbc / Cy) * dt
    dlca = s.dlca + (src.Fyoc * (dlcy - s.dlca) / Ca) * dt
    Rcy = s.Rcy + ((roc - s.Rcy) * bur.Fbc / Cy) * dt
    Rca = s.Rca + ((Rcy - s.Rca) * src.Fyoc / Ca) * dt

    return ReservoirState{T}(oxygen, Gy, Cy, Ca, Ssy, Spy, dlsy, dlcy, dlpy, dlpa, dlgy, dlga, dlsa, dlca, Rcy, Rca)
end
