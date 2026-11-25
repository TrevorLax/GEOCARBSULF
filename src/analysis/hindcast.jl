"""
    hindcast(res::PrecalibrationResult; options = nothing, T0 = res.config["T0"],
             include_geog = true, center = nothing, n = nothing, rng = StableRNG(1))
        -> (co2, temp, idx)

Model CO2 (ppmv) and temperature (°C) of the accepted samples, as `n_time × n`
matrices. Temperatures are `temp + T0` plus, with `include_geog = true`, the GEOG
series of the forcings the model ran on. That is what the R analysis plots against
proxies, but it is **not** the quantity that precalibration
compared with the temperature windows: acceptance uses `temp + T0` only. Use
`include_geog = false` (or [`accepted_temperature`](@ref)) to get the tested quantity.

With `options = nothing`, the model outputs saved during precalibration are reused (no
model runs). Pass a [`ModelOptions`](@ref) to re-run every sample with different
model options, for example the supplemental-experiment variants. `n` subsamples as in
[`parameter_quantiles`](@ref); `idx` are the samples used. `T0` defaults to the value
stored in the result's configuration (15 °C if absent).

Results of experiments with `run_on_time_centers = true` (the R Cretaceous
experiment) ran the model on the forcing *centres*; the saved series were sampled but
never drove the model. For those results:

- the saved outputs are still the ones acceptance used, so `options = nothing` with
  `include_geog = false` works as usual;
- adding GEOG, or re-running the model, needs the centre forcings, which a result does
  not store. Pass them as `center` (for example `prepare_precalibration(cfg).center`);
  otherwise an `ArgumentError` is thrown rather than silently mixing the sampled series
  with outputs computed on the centres.
"""
function hindcast(
    res::PrecalibrationResult;
    options::Union{Nothing,ModelOptions}=nothing,
    T0::Real=_config_T0(res),
    include_geog::Bool=true,
    center::Union{Nothing,TimeForcings}=nothing,
    n=nothing,
    rng::AbstractRNG=StableRNG(1),
)
    on_centers = _ran_on_centers(res)
    if on_centers && center === nothing && (include_geog || options !== nothing)
        throw(
            ArgumentError(
                "result \"$(res.tag)\" was computed with run_on_time_centers = true: the model ran on the " *
                "forcing centres, not on the saved series. Pass the centre forcings as `center` " *
                "(e.g. prepare_precalibration(cfg).center), or use include_geog = false with options = nothing.",
            ),
        )
    end
    if center !== nothing
        center.age == res.age || throw(ArgumentError("center: age grid differs from the result's"))
    end
    idx = subsample_indices(n_accepted(res), n; rng=rng)
    nt = length(res.age)
    co2 = Matrix{Float64}(undef, nt, length(idx))
    temp = Matrix{Float64}(undef, nt, length(idx))
    jgeog = findfirst(==(:GEOG), res.forcing_names)
    out = GeocarbResult{Float64}(res.age)
    for (c, k) in enumerate(idx)
        forcings = on_centers ? center : nothing
        if options === nothing
            co2[:, c] .= view(res.co2, :, k)
            temp[:, c] .= view(res.temp, :, k)
        else
            forcings === nothing && (forcings = sample_forcings(res, k))
            run_geocarb!(out, sample_constants_params(res, k), forcings; options=options)
            co2[:, c] .= out.co2
            temp[:, c] .= out.temp
        end
        temp[:, c] .+= T0
        if include_geog
            temp[:, c] .+= on_centers ? center.GEOG : view(res.time_series, :, k, jgeog)
        end
    end
    return (co2=co2, temp=temp, idx=idx)
end

"""
    accepted_temperature(res::PrecalibrationResult; T0 = res.config["T0"]) -> Matrix

`temp + T0` of every accepted sample (`n_time × n`): exactly the quantity that the
precalibration compared with the temperature windows (see [`percent_outbound`](@ref)).
"""
accepted_temperature(res::PrecalibrationResult; T0::Real=_config_T0(res)) = res.temp .+ T0

_config_T0(res::PrecalibrationResult) = Float64(get(res.config, "T0", PRESENT_TEMPERATURE))
_ran_on_centers(res::PrecalibrationResult) = get(res.config, "run_on_time_centers", false) == true

"""
    result_inputs(res::PrecalibrationResult) -> NamedTuple

The inputs an experiment actually used, rebuilt from the configuration stored in the
result (`res.config`) rather than from the package defaults: `config` (an
[`ExperimentConfig`](@ref)), `prior_table`, `proxy` (with the configured proxy types),
`co2_windows` and `temp_windows` (with the configured `nsig`, on the result's age grid)
and `T0`. Throws an `ArgumentError` naming the file if an input file recorded in the
result no longer exists.
"""
function result_inputs(res::PrecalibrationResult)
    isempty(res.config) && throw(ArgumentError("result \"$(res.tag)\" stores no configuration"))
    cfg = ExperimentConfig(res.config)
    for (k, f) in (("prior_file", cfg.prior_file), ("proxy_file", cfg.proxy_file), ("temperature_file", cfg.temperature_file))
        isfile(f) || throw(ArgumentError("result \"$(res.tag)\": $k recorded in the result not found: $f"))
    end
    proxy = read_proxy_data(cfg.proxy_file; proxies=cfg.proxies)
    tdata = read_temperature_data(cfg.temperature_file)
    return (
        config=cfg,
        prior_table=read_prior_table(cfg.prior_file),
        proxy=proxy,
        co2_windows=co2_windows(proxy, res.age; nsig=cfg.nsig, dt=cfg.model.dt),
        temp_windows=temperature_windows(tdata, res.age; nsig=cfg.nsig),
        T0=cfg.T0,
    )
end
