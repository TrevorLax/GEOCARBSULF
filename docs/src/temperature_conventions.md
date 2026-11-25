# Temperature conventions

The R code used three different temperatures, documented only in comments that
contradict each other (finding F-20). In Julia they are made explicit by
[`temperature`](@ref).

The model output `r.temp = GCM·ln(RCO2) − Ws·t/570` is the temperature change from
CO2 **including** the solar-luminosity term `−Ws·t/570`: the Sun was fainter in the
past, so that term cools. The Mills et al. (2019) windows are actual temperatures and
include the solar effect as well, so the two are compared directly (after adding `T0`).

| quantity | Julia | R |
|:--|:--|:--|
| model output: CO2 warming, solar term included | `r.temp = GCM·ln(RCO2) − Ws·t/570` | `temp_out` in `run_geocarb.f90:556` |
| compared with the Mills et al. (2019) windows | `temperature(r)` = `r.temp .+ T0` ([`accepted_temperature`](@ref) for a result) | `model_out[,"temp"] + 15` (`lhs_sampling.R:137`) |
| plotted as hindcasts by the R code | `temperature(r; geog = f.GEOG)` | `temp + GEOG + 15` (`analysis_and_plots.R:140`) |
| CO2 only, solar term removed | `temperature(r; remove_solar = p.Ws)` | commented out in the R code |

`T0 = 15 °C` is the present-day temperature assumed by Berner (2004, eqs. 2.8 and 2.28);
it is the `T0` of the experiment configuration.

The R hindcast figure added GEOG and plotted the result against the same windows that
acceptance used without GEOG. [`plot_model_vs_proxy`](@ref) plots `temp + T0`, the
quantity that was tested.
