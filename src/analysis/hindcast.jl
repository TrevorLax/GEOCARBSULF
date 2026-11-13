"""
    hindcast(res::PrecalibrationResult; options = nothing, T0 = 15.0, include_geog = true,
             n = nothing, rng = StableRNG(1)) -> (co2, temp, idx)

Model CO2 (ppmv) and temperature (°C) of the accepted samples, as `n_time × n`
matrices. Temperatures are `temp + T0` plus, with `include_geog = true`, the sample's
GEOG series, which is what the R analysis plots against proxies
(`analysis_and_plots.R:140`).

With `options = nothing`, the model outputs saved during precalibration are reused (no
model runs). Pass a [`ModelOptions`](@ref) to re-run every sample with different
model options, for example the supplemental-experiment variants. `n` subsamples as in
[`parameter_quantiles`](@ref); `idx` are the samples used.
"""
function hindcast(
    res::PrecalibrationResult;
    options::Union{Nothing,ModelOptions}=nothing,
    T0::Real=PRESENT_TEMPERATURE,
    include_geog::Bool=true,
    n=nothing,
    rng::AbstractRNG=StableRNG(1),
)
    idx = subsample_indices(n_accepted(res), n; rng=rng)
    nt = length(res.age)
    co2 = Matrix{Float64}(undef, nt, length(idx))
    temp = Matrix{Float64}(undef, nt, length(idx))
    jgeog = findfirst(==(:GEOG), res.forcing_names)
    out = GeocarbResult{Float64}(res.age)
    for (c, k) in enumerate(idx)
        if options === nothing
            co2[:, c] .= view(res.co2, :, k)
            temp[:, c] .= view(res.temp, :, k)
        else
            run_geocarb!(out, sample_constants_params(res, k), sample_forcings(res, k); options=options)
            co2[:, c] .= out.co2
            temp[:, c] .= out.temp
        end
        temp[:, c] .+= T0
        include_geog && (temp[:, c] .+= view(res.time_series, :, k, jgeog))
    end
    return (co2=co2, temp=temp, idx=idx)
end
