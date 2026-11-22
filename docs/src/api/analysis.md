# Analysis and plotting API

Summaries of a precalibration result, and the plotting functions.

## Summaries

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/analysis/summaries.jl"]
Order = [:module, :constant, :type, :function]
```

## Correlations and survival

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/analysis/correlations.jl"]
Order = [:module, :constant, :type, :function]
```

## Kernel density estimates

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/analysis/kde.jl"]
Order = [:module, :constant, :type, :function]
```

## Climate sensitivity

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/analysis/sensitivity_numbers.jl"]
Order = [:module, :constant, :type, :function]
```

## Hindcast

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/analysis/hindcast.jl"]
Order = [:module, :constant, :type, :function]
```

## Plotting

The methods are defined in the package extension `ext/GeocarbMakieExt.jl`, which loads
when a Makie backend is loaded (`using CairoMakie`). Without one these functions have
no methods.

```@autodocs
Modules = [GeocarbPrecalibration]
Pages = ["src/plotting.jl"]
Order = [:module, :constant, :type, :function]
```
