"""
    PrecalibrationResult

Accepted samples of a precalibration experiment.

| field | shape | meaning |
|:--|:--|:--|
| `tag` | | experiment tag, for example `"ct_out30"` |
| `config_text` | | the TOML text the experiment came from (if any) |
| `config` | | `Dict` summary of the [`ExperimentConfig`](@ref) |
| `age` | `n_time` | age grid (Myr ago) |
| `constant_names` | 56 | [`CONSTANT_PARAMETER_NAMES`](@ref) |
| `constants` | `n × 56` | accepted constant parameters (all 56, fixed ones included) |
| `forcing_names` | 12 | [`TIME_FORCING_NAMES`](@ref) |
| `time_series` | `n_time × n × 12` | accepted forcing series (after normalisation) |
| `co2`, `o2`, `temp` | `n_time × n` | model output of the accepted samples (`temp` as returned by the model, *without* `+T0`) |
| `status` | `n_time × n` | `UInt8(StepStatus)` per step |
| `prcout_co2`, `prcout_temp` | `n` | legacy % outbound of CO2 and of `temp + T0` |
| `sample_keys` | `n × 2` | `(chunk, index within chunk)`: enough to regenerate any sample |
| `n_simulated` | | number of simulations run |
| `covariances` | `n_time × n_time × n × 12` or `nothing` | inverse-Wishart draws, only with `save_covariances = true` |
| `provenance` | | versions, git commit, timings, threads |
"""
struct PrecalibrationResult
    tag::String
    config_text::String
    config::Dict{String,Any}
    age::Vector{Float64}
    constant_names::Vector{Symbol}
    constants::Matrix{Float64}
    forcing_names::Vector{Symbol}
    time_series::Array{Float64,3}
    co2::Matrix{Float64}
    o2::Matrix{Float64}
    temp::Matrix{Float64}
    status::Matrix{UInt8}
    prcout_co2::Vector{Float64}
    prcout_temp::Vector{Float64}
    sample_keys::Matrix{Int}
    n_simulated::Int
    covariances::Union{Nothing,Array{Float64,4}}
    provenance::Dict{String,String}
end

"""
    n_accepted(res::PrecalibrationResult) -> Int
"""
n_accepted(res::PrecalibrationResult) = size(res.constants, 1)

"""
    constant_column(res, name::Symbol) -> Vector{Float64}

Accepted values of one constant parameter.
"""
function constant_column(res::PrecalibrationResult, name::Symbol)
    j = findfirst(==(name), res.constant_names)
    j === nothing && throw(ArgumentError("unknown constant parameter :$name"))
    return res.constants[:, j]
end

"""
    forcing_series(res, name::Symbol) -> Matrix{Float64}

`n_time × n` accepted series of one forcing.
"""
function forcing_series(res::PrecalibrationResult, name::Symbol)
    j = findfirst(==(name), res.forcing_names)
    j === nothing && throw(ArgumentError("unknown forcing :$name"))
    return res.time_series[:, :, j]
end

"""
    sample_constants_params(res, k) -> ConstantParams{Float64}

Constant parameters of accepted sample `k`.
"""
sample_constants_params(res::PrecalibrationResult, k::Integer) = ConstantParams(res.constant_names, res.constants[k, :])

"""
    sample_forcings(res, k) -> TimeForcings{Float64}

Forcings of accepted sample `k`.
"""
function sample_forcings(res::PrecalibrationResult, k::Integer)
    d = Dict{Symbol,Vector{Float64}}(n => res.time_series[:, k, j] for (j, n) in enumerate(res.forcing_names))
    return TimeForcings(res.age, d; check_finite=false)
end

function Base.show(io::IO, ::MIME"text/plain", res::PrecalibrationResult)
    println(
        io, "PrecalibrationResult \"", res.tag, "\": ", n_accepted(res), " accepted of ", res.n_simulated, " simulated"
    )
    return print(
        io,
        "  age grid: ",
        length(res.age),
        " steps; covariances ",
        res.covariances === nothing ? "not stored" : "stored",
    )
end

"""
    merge_results(results; tag = results[1].tag) -> PrecalibrationResult

Concatenate the accepted samples of several results on the same age grid, for example
the three seeds of the 30 % CO2 + temperature experiment (`analysis_and_plots.R:61-77`).
`n_simulated` is summed; covariances are kept only if every result has them.
"""
function merge_results(results::AbstractVector{PrecalibrationResult}; tag::AbstractString=first(results).tag)
    isempty(results) && throw(ArgumentError("nothing to merge"))
    r1 = first(results)
    for r in results
        r.age == r1.age || throw(ArgumentError("age grids differ"))
        r.constant_names == r1.constant_names || throw(ArgumentError("constant names differ"))
        r.forcing_names == r1.forcing_names || throw(ArgumentError("forcing names differ"))
    end
    covs = all(r -> r.covariances !== nothing, results) ? cat((r.covariances for r in results)...; dims=3) : nothing
    prov = Dict{String,String}("merged_from" => join((r.tag for r in results), ", "))
    for (i, r) in enumerate(results), (k, v) in r.provenance
        prov["part$(i)_$k"] = v
    end
    return PrecalibrationResult(
        String(tag),
        r1.config_text,
        r1.config,
        copy(r1.age),
        copy(r1.constant_names),
        reduce(vcat, [r.constants for r in results]),
        copy(r1.forcing_names),
        cat((r.time_series for r in results)...; dims=2),
        reduce(hcat, [r.co2 for r in results]),
        reduce(hcat, [r.o2 for r in results]),
        reduce(hcat, [r.temp for r in results]),
        reduce(hcat, [r.status for r in results]),
        reduce(vcat, [r.prcout_co2 for r in results]),
        reduce(vcat, [r.prcout_temp for r in results]),
        reduce(vcat, [r.sample_keys for r in results]),
        sum(r.n_simulated for r in results),
        covs,
        prov,
    )
end
