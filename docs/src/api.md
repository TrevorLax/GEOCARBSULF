# API

The reference is split by area. Each page lists the docstrings of the source files
named in its sections, public and internal.

| page | covers |
|:--|:--|
| [Model](api/model.md) | `run_geocarb`, results, fluxes, CO2 solver, climate, vegetation, constants (`src/model/`, `src/constants.jl`, `src/numerics.jl`) |
| [Parameters and priors](api/parameters.md) | parameter names, `ConstantParams`, `TimeForcings`, `ModelOptions`, truncated priors (`src/parameters/`, `src/priors/`) |
| [Samplers](api/sampling.md) | Latin hypercube, constant-parameter designs, time-series samplers (`src/sampling/`) |
| [Input data and output files](api/data.md) | input CSV readers, proxy and temperature data, saving and loading results (`src/io/`) |
| [Constraints and precalibration](api/constraints.md) | windows, % outbound, acceptance rules, experiment configurations, the engine (`src/constraints/`, `src/precalibration/`) |
| [Analysis and plotting](api/analysis.md) | summaries, correlations, KDE, climate sensitivity, hindcast, plotting (`src/analysis/`, `src/plotting.jl`) |

!!! note "Adding a source file"
    The pages select docstrings by source file (`Pages = [...]` in each `@autodocs`
    block). A new file under `src/` with docstrings must be added to one of them;
    `docs/make.jl` fails the build if a docstring's file is on no page.

## The package

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/GeocarbPrecalibration.jl"]
Order = [:module, :constant, :type, :function]
```

## Timing instrumentation

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/timing.jl"]
Order = [:module, :constant, :type, :function]
```
