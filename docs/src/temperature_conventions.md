# Temperature conventions

The R code used three different temperatures, documented only in comments that
contradict each other (finding F-20). In Julia they are made explicit by
[`temperature`](@ref):

| quantity | Julia | R |
|:--|:--|:--|
| model output: CO2 warming minus the solar term | `r.temp = GCM·ln(RCO2) − Ws·t/570` | `temp_out` in `run_geocarb.f90:556` |
| compared with the Mills et al. (2019) windows | `temperature(r)` = `r.temp .+ 15` | `model_out[,"temp"] + 15` (`lhs_sampling.R:137`) |
| plotted as hindcasts | `temperature(r; geog = f.GEOG)` | `temp + GEOG + 15` (`analysis_and_plots.R:140`) |
| with the solar term added back | `temperature(r; Ws = p.Ws)` | commented out in the R code |

`T0 = 15 °C` is the present-day temperature assumed by Berner (2004, eqs. 2.8 and 2.28).
