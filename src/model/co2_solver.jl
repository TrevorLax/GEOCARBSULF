# Iterative solution for atmospheric CO2 (f90:418-521).
#
# Silicate weathering required by mass balance (`fwsi_no_climate`) must equal the
# climatic weathering factor `fwsi_climate(RCO2)` (Berner 2004 eqs. 2.6-7, 2.29, 5.2;
# pp. 72-76). The equation is solved with a damped Newton iteration (the FORTRAN code of
# Park & Royer 2011). There are three regimes:
#
#   t ∈ (380, 570]  non-vascular plants  (`_nonvascular_terms`)
#   t ∈ (350, 380]  linear blend of the two expressions
#   t ∈ [0, 350]    vascular plants      (`_vascular_terms`)
#
# Every expression below is written in the same order of operations as the Fortran so
# that results agree to rounding error. Do not "simplify" them without re-running the
# legacy comparison test (test/legacy_comparison).

# Non-vascular regime. Returns (fwsi_climate, W, V), where W + V is the slope used by
# the Newton step.
#
# `v_time_grouped` reproduces a quirk of the Fortran: in the pure non-vascular regime V
# uses exp(-ACT*Ws*t/570) (f90:443), while in the blended regime it uses
# exp(-ACT*Ws*(t/570)) (f90:469). The two differ only by rounding.
#
# `corrected` (finding F-01): the Fortran uses RCO2^(-exp_fnBb + ACT*GCM) in W, which is
# the correct derivative only when exp_fnBb = 0.5. The exact exponent is
# exp_fnBb + ACT*GCM - 1.
@inline function _nonvascular_terms(R, t, RT, GEOG, gcm, p::ConstantParams, corrected::Bool, v_time_grouped::Bool)
    lr = nanlog(R)
    base = 1 + RT * gcm * lr - RT * p.Ws * (t / AGE_MAX) + RT * GEOG
    e = p.exp_fnBb + p.ACT * gcm
    e1 = exp(-p.ACT * p.Ws * (t / AGE_MAX))
    e2 = exp(p.ACT * GEOG)
    fw = nanpow(R, e) * nanpow(base, p.exp_fD) * e1 * e2
    wexp = corrected ? (p.exp_fnBb + p.ACT * gcm - 1) : (-p.exp_fnBb + p.ACT * gcm)
    W = (e * nanpow(R, wexp)) * nanpow(base, p.exp_fD) * e1 * e2
    e1v = v_time_grouped ? e1 : exp(-p.ACT * p.Ws * t / AGE_MAX)
    V = nanpow(R, e) * p.exp_fD * nanpow(base, -(1 - p.exp_fD)) * (RT * gcm / R) * e1v * e2
    return fw, W, V
end

# Vascular regime. Returns (fwsi_climate, W, V, X); W + V + X is the slope.
@inline function _vascular_terms(R, t, RT, GEOG, gcm, p::ConstantParams)
    lr = nanlog(R)
    base = 1 + RT * gcm * lr - RT * p.Ws * (t / AGE_MAX) + RT * GEOG
    g = p.FERT + p.ACT * gcm
    tf = 2.0^p.FERT
    e1 = exp(-p.ACT * p.Ws * (t / AGE_MAX))
    e2 = exp(p.ACT * GEOG)
    fw = (tf * nanpow(R, g)) * nanpow(1 + R, -p.FERT) * nanpow(base, p.exp_fD) * e1 * e2
    W = tf * g * nanpow(R, g - 1) * nanpow(1 + R, -p.FERT) * nanpow(base, p.exp_fD) * e1 * e2
    V = (-p.FERT * nanpow(1 + R, -(1 + p.FERT))) * (tf * nanpow(R, g)) * nanpow(base, p.exp_fD) * e1 * e2
    X = p.exp_fD * nanpow(base, -(1 - p.exp_fD)) * (RT * gcm / R) * (tf * nanpow(R, g)) *
        nanpow(1 + R, -p.FERT) * e1 * e2
    return fw, W, V, X
end

"""
    solve_rco2(t, rco2, fwsi_nc, gcm, RT, GEOG, p, o, k) -> (rco2, status, iterations)

Damped Newton solve for RCO2 (CO2 relative to 250 ppmv) at age `t`, starting from the
previous step's value. Returns the new RCO2, a [`StepStatus`](@ref) (`Converged`,
`NotConverged` or `NaNEncountered`) and the number of iterations.

The convergence test, damping, fallback shrinkage and failure rules are those of the
Fortran (f90:431-521). In particular, convergence is judged on the *relative step size*
(`abs(RCO2/RCO2_old − 1) ≤ tol`), and the iteration at which `count ==
iteration_threshold` is counted as a failure.
"""
@inline function solve_rco2(t::Real, rco2, fwsi_nc, gcm, RT, GEOG, p::ConstantParams,
                            o::ModelOptions, k::ResolvedConstants)
    rco2_old = 2 * rco2   # guarantees at least one iteration (f90:431)
    count = 0
    status = Converged

    if t <= AGE_MAX && t > AGE_VASCULAR_RAMP_START
        while abs((rco2 / rco2_old) - 1) > k.tol
            count += 1
            rco2_old = rco2
            fw, W, V = _nonvascular_terms(rco2, t, RT, GEOG, gcm, p, o.corrected_newton_derivative, false)
            nan = isnan(fw + W + V)
            if nan || count == o.iteration_threshold
                status = nan ? NaNEncountered : NotConverged
                break
            end
            step = (fw - fwsi_nc) / (W + V)
            rco2 = rco2 > step ? rco2 - k.damping * step : k.shrink * rco2
        end
    end

    if t <= AGE_VASCULAR_RAMP_START && t > AGE_GYMNOSPERM && status == Converged
        while abs((rco2 / rco2_old) - 1) > k.tol
            count += 1
            rco2_old = rco2
            fwo, Wo, Vo = _nonvascular_terms(rco2, t, RT, GEOG, gcm, p, o.corrected_newton_derivative, true)
            fwn, Wn, Vn, Xn = _vascular_terms(rco2, t, RT, GEOG, gcm, p)
            fw = (t - AGE_GYMNOSPERM) / BLEND_DENOMINATOR * fwo + (BLEND_UPPER - t) / BLEND_DENOMINATOR * fwn
            slope = (t - AGE_GYMNOSPERM) / BLEND_DENOMINATOR * (Wo + Vo) +
                    (BLEND_UPPER - t) / BLEND_DENOMINATOR * (Wn + Vn + Xn)
            nan = isnan(fwo + Wo + Vo + fwn + Wn + Vn + Xn + fw + slope)
            if nan || count == o.iteration_threshold
                status = nan ? NaNEncountered : NotConverged
                break
            end
            step = (fw - fwsi_nc) / slope
            rco2 = rco2 > step ? rco2 - k.damping * step : k.shrink * rco2
        end
    end

    if t <= AGE_GYMNOSPERM && status == Converged
        while abs((rco2 / rco2_old) - 1) > k.tol
            count += 1
            rco2_old = rco2
            fw, W, V, X = _vascular_terms(rco2, t, RT, GEOG, gcm, p)
            nan = isnan(fw + W + V + X)
            if nan || count == o.iteration_threshold
                status = nan ? NaNEncountered : NotConverged
                break
            end
            step = (fw - fwsi_nc) / (W + V + X)
            rco2 = rco2 > step ? rco2 - k.damping * step : k.shrink * rco2
        end
    end

    return rco2, status, count
end
