# The model

```@meta
DocTestSetup = :(using GeocarbPrecalibration)
```

GEOCARBSULFvolc (Berner 2004, 2006a, 2006b, 2008; Royer et al. 2014) tracks the long-term
carbon and sulfur cycles from 570 Ma to the present in 10 Myr steps. At each step it
solves for the atmospheric CO2 level that balances silicate weathering against the
carbon that must be removed by mass balance. The Julia code is a line-by-line port of
`fortran/src/run_geocarb.f90`, split into small functions:

| step | function | Fortran lines |
|:--|:--|:--|
| climate sensitivity factor GCM (glacial intervals, optional ΔT2x ramp) | `gcm_factor` | 309–315 |
| plant effects on weathering `fE` and `fBB` | `vegetation_fE`, `carbonate_fBB` | 319–359 |
| weathering and degassing fluxes | `source_fluxes` | 363–378 |
| isotopic fractionations and burial fluxes | `isotope_fractionations`, `burial_fluxes` | 381–390 |
| volcanic weathering (Sr isotopes) | `volcanic_weathering` | 393–400 |
| atmospheric O2 | `update_oxygen` | 403–405 |
| silicate weathering required by mass balance | `silicate_weathering_no_climate` | 416 |
| damped Newton solve for RCO2 (three vegetation regimes) | `solve_rco2` | 431–521 |
| reservoir and isotope updates | `update_reservoirs` | 529–545 |
| outputs and failure checks | `run_geocarb!` | 547–566 |

Key relations (Berner 2004):

- climate: ``\Delta T_{2\times} = \Gamma \ln 2``, with ``\Gamma`` multiplied by `GLAC`
  in glacial intervals (260–330 Ma and ≤ 40 Ma);
- temperature: ``T(t) - T_0 = \Gamma \ln R_{CO_2} - W_s t/570 + \mathrm{GEOG}(t)``;
- silicate weathering: the climatic factor ``f_{B}(R_{CO_2})`` is set equal to the
  value required by mass balance, ``(F_{bc} - F_{wcy} - F_{wca}) / (f_{Aw}f_A f_D)^{exp_{fD}} f_E f_R f_{volc} F_{wsi,0}``.

## Failure handling

The model never throws because of parameter values. Each step gets a
[`StepStatus`](@ref), and the Fortran output conventions are kept: `co2` and `o2` are
`Inf` on failed steps. `temp` is not, which is why temperature-only experiments can
accept failed runs in the R code (finding F-04; see `reject_failed_runs`).

## Options and supplemental experiments

[`ModelOptions`](@ref) replaces the second Fortran subroutine `run_geocarb_supp.f90`.
For example, the "gym+timing+dT2X" experiment is

```jldoctest
julia> table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"));

julia> f = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv")).center;

julia> opts = ModelOptions(gym_angio_transition = (110, 60), gym_factor = 0.25, dT2X_ramp = true);

julia> r = run_geocarb(mean_constants(table), f; options = opts);

julia> succeeded(r), round(r.co2[end]; digits = 1)
(true, 243.6)
```

Two options control numerics that deliberately follow the legacy code by default:

- `fortran_single_literals` (default `true`) rounds the decimal literals of the
  Fortran (`0.01, 0.9, 0.2, 0.7, 0.6, 0.8, 1.2`, `log(2.0)`) to single precision, as
  gfortran does, so the default reproduces the compiled legacy code up to library
  rounding. `false` uses Float64 literals; this is a *model change* (it flips the
  pass/fail outcome of about 10 % of prior draws), not a precision improvement.
- `corrected_newton_derivative` (default `false`); `true` uses the exact Newton
  derivative before 380 Ma (finding F-01).

## References

- Berner, R. A. (2004). *The Phanerozoic Carbon Cycle: CO2 and O2.* Oxford University Press.
- Berner, R. A. (2006a). GEOCARBSULF: a combined model for Phanerozoic atmospheric O2 and CO2. *GCA* 70, 5653–5664.
- Berner, R. A. (2006b). Inclusion of the weathering of volcanic rocks in the GEOCARBSULF model. *AJS* 306, 295–302.
- Berner, R. A. (2008). Addendum to "Inclusion of the weathering of volcanic rocks in the GEOCARBSULF model". *AJS* 308, 100–103.
- Goddéris, Y., et al. (2012), the source of the `*_Godderis` arrays (as cited in the original `parameterSetup.R`).
- Krause, A. J., et al. (2018). Stepwise oxygenation of the Paleozoic atmosphere. *Nature Communications* 9, 4081.
- Mills, B. J. W., et al. (2019). Modelling the long-term carbon cycle, atmospheric CO2, and Earth surface temperature from late Neoproterozoic to present day. *Gondwana Research* 67, 172–186.
- Park, J., & Royer, D. L. (2011). Geologic constraints on the glacial amplification of Phanerozoic climate sensitivity. *AJS* 311, 1–26.
- Royer, D. L., et al. (2014). Error analysis of CO2 and O2 estimates from the long-term geochemical model GEOCARBSULF. *AJS* 314, 1259–1283.
- Wong, T. E., Cui, Y., Royer, D. L., & Keller, K. (2021). A tighter constraint on Earth-system sensitivity from long-term temperature and carbon-cycle observations. *Nature Communications* 12, 3173.
