"""
    volcanic_weathering(i, src, bur, s, p, f, k) -> (Roc, Xvolc, fvolc)

Volcanic / non-volcanic silicate weathering, the "volc" in GEOCARBSULFvolc (Berner
2006b, 2008; f90:393-400):

- `Roc`: 87Sr/86Sr of seawater as recorded in carbonates, `Sr/10^4 + 0.7`;
- `Rg`: 87Sr/86Sr of non-volcanic silicates (`Rnv` in Berner 2006b);
- `Xvolc`: fraction of Ca and Mg silicate weathering derived from volcanic rocks;
- `fvolc`: volcanic weathering effect relative to the present.
"""
@inline function volcanic_weathering(i::Int, src, bur, s::ReservoirState, p::ConstantParams,
                                     f::TimeForcings, k::ResolvedConstants)
    roc = (f.Sr[i] / SR_SCALE) + k.sr_offset
    Rg = p.Rg_570 - p.NV * (1 - nanpow(f.fR[i], 1 / p.exp_NV))
    A = ((p.Rv_570 - roc) * f.fSR[i] * p.Fob) / (bur.Fbc - src.Fwcy - src.Fwca)
    B = src.Fwcy / (bur.Fbc - src.Fwcy - src.Fwca)
    D = src.Fwca / (bur.Fbc - src.Fwcy - src.Fwca)
    E = bur.Fbc / (bur.Fbc - src.Fwcy - src.Fwca)
    xvolc = (A + B * s.Rcy + D * s.Rca - E * roc + Rg) / (Rg - p.Rv_570)
    return roc, xvolc, volcanic_weathering_factor(xvolc, p)
end

"""
    volcanic_weathering_factor(Xvolc, p) -> fvolc

`fvolc = (VNV·Xvolc + 1 − Xvolc) / (VNV·Xvolc_0 + 1 − Xvolc_0)`, equal to 1 when
`Xvolc == Xvolc_0` (f90:400).
"""
@inline volcanic_weathering_factor(xvolc, p::ConstantParams) =
    (p.VNV * xvolc + 1 - xvolc) / (p.VNV * p.Xvolc_0 + 1 - p.Xvolc_0)
