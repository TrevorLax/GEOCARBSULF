"""
    in_glacial_interval(t, o::ModelOptions) -> Bool

`true` if age `t` (Myr ago) lies in one of the closed intervals `o.glacial_intervals`.
With the defaults this is `(260 ≤ t ≤ 330) || t ≤ 40` (f90:309). That follows Fielding
et al. (2008); the original BASIC code used 270–340 Ma.
"""
@inline function in_glacial_interval(t::Real, o::ModelOptions)
    for (lo, hi) in o.glacial_intervals
        if lo <= t <= hi
            return true
        end
    end
    return false
end

"""
    gcm_factor(t, p, o, k) -> GCM

Climate-sensitivity factor `GCM` ("capital gamma" in Berner 2004), with
`deltaT2X = GCM·ln 2`:

- in glacial intervals: `GCM = GLAC·deltaT2X / ln 2`;
- otherwise, if `o.dT2X_ramp` and `t ∈ (end, start]` of `o.dT2X_ramp_interval`, the
  supplemental ramp: `fac = (GLAC·(start − t) + (t − end)) / (start − end)`,
  `GCM = fac·deltaT2X / ln 2` (`run_geocarb_supp.f90:324-336`);
- otherwise `GCM = deltaT2X / ln 2`.

`k` are the [`ResolvedConstants`](@ref) (they carry `ln 2`, possibly rounded to single
precision as in the Fortran).
"""
@inline function gcm_factor(t::Real, p::ConstantParams, o::ModelOptions, k::ResolvedConstants)
    if in_glacial_interval(t, o)
        return p.GLAC * p.deltaT2X / k.ln2
    end
    if o.dT2X_ramp
        a, b = o.dT2X_ramp_interval
        if t <= a && t > b
            fac = (p.GLAC * (a - t) + (t - b)) / (a - b)
            return fac * p.deltaT2X / k.ln2
        end
    end
    return p.deltaT2X / k.ln2
end
