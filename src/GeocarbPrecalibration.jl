"""
    GeocarbPrecalibration

Julia implementation of the GEOCARBSULFvolc long-term carbon-cycle model (Berner 2004,
2006a/b, 2008; Royer et al. 2014) and of the Latin-hypercube *precalibration*
workflow of Wong et al. (2021), ported from the R/Fortran code in
`GEOCARB-precalibration`.

The package is organised in layers that only depend on the layers above them:

1. `parameters/`: named parameter, forcing and option types
2. `model/`: the model itself ([`run_geocarb`](@ref), [`run_geocarb!`](@ref))
3. `io/`: readers for the input CSV files and writers for results
4. `priors/`, `sampling/`: prior distributions, Latin hypercube and time-series samplers
5. `constraints/`: precalibration windows and the "percent outbound" metric
6. `precalibration/`: experiment configuration, acceptance rules and the chunked,
   threaded, deterministic sampling engine ([`run_precalibration`](@ref))
7. `analysis/`: summaries used in the manuscript (quantiles, KDEs, correlations, ...)

Plotting lives in the `GeocarbMakieExt` package extension and is only loaded together
with a Makie backend (for example `using CairoMakie`).
"""
module GeocarbPrecalibration

using Dates: Dates
using Distributions: Distributions, Chisq, LogNormal, Normal, Uniform
using JLD2: JLD2
using LinearAlgebra: LinearAlgebra, LowerTriangular
using Printf: @sprintf
using Random: Random, AbstractRNG, randperm
using StableRNGs: StableRNG
using Statistics: Statistics, mean, median, std, var
using StatsBase: StatsBase
using TOML: TOML
using TimerOutputs: TimerOutputs, TimerOutput, @timeit_debug

include("constants.jl")
include("timing.jl")
include("numerics.jl")

include("parameters/names.jl")
include("parameters/constant_params.jl")
include("parameters/time_forcings.jl")
include("parameters/options.jl")

include("model/result.jl")
include("model/state.jl")
include("model/climate.jl")
include("model/vegetation.jl")
include("model/fluxes.jl")
include("model/strontium.jl")
include("model/co2_solver.jl")
include("model/geocarb.jl")

include("io/csv_utils.jl")
include("io/priors_csv.jl")
include("io/time_arrays_csv.jl")
include("io/proxy_data.jl")
include("io/temperature_data.jl")

include("priors/priors.jl")

include("sampling/lhs.jl")
include("sampling/constant_sampler.jl")
include("sampling/time_series_sampler.jl")

include("constraints/windows.jl")
include("constraints/percent_outbound.jl")

include("precalibration/config.jl")
include("precalibration/acceptance.jl")
include("precalibration/result.jl")
include("precalibration/run.jl")

include("io/outputs.jl")

include("analysis/summaries.jl")
include("analysis/kde.jl")
include("analysis/hindcast.jl")
include("analysis/sensitivity_numbers.jl")
include("analysis/correlations.jl")

include("plotting.jl")

# --- parameters -----------------------------------------------------------------
export CONSTANT_PARAMETER_NAMES, TIME_FORCING_NAMES
export ConstantParams, TimeForcings, ModelOptions
export parameter_vector, update, parameter_description, parameter_units
# --- model ----------------------------------------------------------------------
export StepStatus, Converged, NotConverged, NaNEncountered, RCO2OutOfRange, PresentDayCheckFailed, InvalidState
export GeocarbResult, run_geocarb, run_geocarb!, succeeded, temperature
# --- inputs ---------------------------------------------------------------------
export datapath,
    read_csv_table,
    read_prior_table,
    read_time_arrays,
    read_proxy_data,
    read_temperature_data,
    read_park_royer_2011,
    mean_constants
export PriorSpec, PriorTable, TimeArrayPrior, ProxyData, TemperatureData
# --- priors and samplers --------------------------------------------------------
export TruncatedPrior, build_priors, quantile_from_unit, random_lhs
export ChunkedLHS, GlobalLHS, sample_constants
export TimeSeriesSampler,
    InverseWishartSampler, MultivariateTSampler, inverse_wishart_dof, read_variance_reduction, sample_time_forcings!
# --- constraints ----------------------------------------------------------------
export Windows, co2_windows, temperature_windows, legacy_percent_outbound, percent_outbound
# --- precalibration -------------------------------------------------------------
export ExperimentConfig, load_experiments, validate, with_overrides, default_tag
export AcceptanceRule, OutboundRule, AllOf, CretaceousWindowRule, build_rule
export PrecalibrationResult,
    run_precalibration,
    n_accepted,
    constant_column,
    forcing_series,
    save_result,
    load_result,
    write_summary_csvs,
    merge_results,
    prepare_precalibration,
    accepts,
    EvaluationContext
# --- analysis -------------------------------------------------------------------
export DEFAULT_PROBS,
    parameter_quantiles,
    time_series_quantiles,
    prior_posterior_table,
    hindcast,
    row_quantiles,
    gaussian_kde,
    bw_nrd0,
    climate_sensitivity_summary,
    linear_interpolator,
    correlation_screen,
    acf_quantiles,
    survival_curve
# --- plotting (implemented in GeocarbMakieExt) -----------------------------------
export plot_model_vs_proxy,
    plot_deltaT2X_distributions,
    plot_deltaT2X_experiments,
    plot_time_series_parameters,
    plot_co2_windows_and_proxies,
    plot_gym_modification,
    plot_time_series_autocorrelations

end # module
