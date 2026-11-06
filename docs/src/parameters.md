# Parameters

The 56 constant parameters and 12 time-varying forcings, with their meaning and units.
The table is generated from `src/parameters/names.jl`, the single source of truth for
names.

```@eval
using GeocarbPrecalibration, Markdown
const G = GeocarbPrecalibration
table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
rows = ["| name | meaning | units | prior | bounds |", "|:--|:--|:--|:--|:--|"]
for n in CONSTANT_PARAMETER_NAMES
    s = G.spec(table, n)
    prior = s.distribution == :lognormal ? "log-normal, median $(s.mean), factor $(s.two_sigma/2)" :
            "$(s.distribution), mean $(s.mean), 2σ $(s.two_sigma)"
    push!(rows, "| `$n` | $(parameter_description(n)) | $(parameter_units(n)) | $prior | [$(s.lower), $(s.upper)] |")
end
push!(rows, "", "| forcing | meaning | units |", "|:--|:--|:--|")
for n in TIME_FORCING_NAMES
    push!(rows, "| `$n` | $(parameter_description(n)) | $(parameter_units(n)) |")
end
Markdown.parse(join(rows, "\n"))
```
