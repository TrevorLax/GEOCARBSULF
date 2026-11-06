"""
    vegetation_fE(t, p, o) -> fE

Effect of plants on the weathering rate at age `t` relative to the present
(f90:319-359; supplemental variant `run_geocarb_supp.f90:374-395`):

| age (Myr ago) | fE |
|:--|:--|
| (380, 570] | `LIFE` (non-vascular plants) |
| (350, 380] | linear ramp `LIFE → GYM` |
| (start, 350] | `GYM` (gymnosperms) |
| (end, start] | linear ramp `gym_factor·GYM → 1` |
| [0, end] | `1` (angiosperms) |

`(start, end) = o.gym_angio_transition`, default `(130, 80)`. The Fortran checks the
intervals one after another, with later checks overriding earlier ones; that order is
kept. Unlike the Fortran supplemental code, `GYM` is never modified in place, so
`gym_factor = 0` is well defined (finding F-09).
"""
@inline function vegetation_fE(t::Real, p::ConstantParams, o::ModelOptions)
    beg, en = o.gym_angio_transition
    fE = p.LIFE * NaN
    if t <= AGE_MAX && t > AGE_VASCULAR_RAMP_START
        fE = p.LIFE
    end
    if t <= AGE_VASCULAR_RAMP_START && t > AGE_GYMNOSPERM
        fE = (p.GYM - p.LIFE) * ((AGE_VASCULAR_RAMP_START - t) / VASCULAR_RAMP_LENGTH) + p.LIFE
    end
    if t <= AGE_GYMNOSPERM && t > beg
        fE = p.GYM
    end
    gym = p.GYM * o.gym_factor
    if t <= beg && t > en
        fE = (1 - gym) * ((beg - t) / (beg - en)) + gym
    end
    if t <= en
        fE = one(fE)
    end
    return fE
end

"""
    carbonate_fBB(t, rco2_prev, gcm, GEOG, p) -> fBB

Effect of climate and CO2 on carbonate weathering (Berner 2004 eqs. 2.6-2.7, 2.29),
using RCO2 from the *previous* time step (f90:325, 336-343). Between 380 and 350 Ma the
non-vascular and vascular expressions are blended linearly.
"""
@inline function carbonate_fBB(t::Real, rco2, gcm, GEOG, p::ConstantParams)
    lr = nanlog(rco2)
    A = 1 + p.ACTcarb * gcm * lr - p.ACTcarb * p.Ws * (t / AGE_MAX) + p.ACTcarb * GEOG
    fBB = A * NaN
    if t <= AGE_MAX && t > AGE_VASCULAR_RAMP_START
        fBB = A * nanpow(rco2, p.exp_fnBb)
    end
    if t <= AGE_VASCULAR_RAMP_START && t > AGE_GYMNOSPERM
        fBB = ((AGE_VASCULAR_RAMP_START - t) / VASCULAR_RAMP_LENGTH) * (A * nanpow(2 * rco2 / (1 + rco2), p.FERT)) +
              ((t - AGE_GYMNOSPERM) / VASCULAR_RAMP_LENGTH) * A * nanpow(rco2, p.exp_fnBb)
    end
    if t <= AGE_GYMNOSPERM
        fBB = A * nanpow(2 * rco2 / (1 + rco2), p.FERT)
    end
    return fBB
end
