# Constraints and precalibration API

CO2 and temperature windows, % outbound, acceptance rules, experiment configurations, and the precalibration engine and its results.

## Windows

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/constraints/windows.jl"]
Order = [:module, :constant, :type, :function]
```

## Percent outbound

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/constraints/percent_outbound.jl"]
Order = [:module, :constant, :type, :function]
```

## Acceptance rules

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/precalibration/acceptance.jl"]
Order = [:module, :constant, :type, :function]
```

## Experiment configuration

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/precalibration/config.jl"]
Order = [:module, :constant, :type, :function]
```

## Running a precalibration

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/precalibration/run.jl"]
Order = [:module, :constant, :type, :function]
```

## Precalibration results

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/precalibration/result.jl"]
Order = [:module, :constant, :type, :function]
```
