"""
    save_result(path, res::PrecalibrationResult) -> path

Write a result to a JLD2 file (HDF5-based; also readable from Python/R HDF5 tools).
Only plain arrays, strings and dictionaries of strings are stored, so the file does not
depend on Julia type definitions.
"""
function save_result(path::AbstractString, res::PrecalibrationResult)
    mkpath(dirname(abspath(path)))
    JLD2.jldsave(
        path;
        format_version=1,
        tag=res.tag,
        config_text=res.config_text,
        config_toml=sprint(io -> TOML.print(io, _tomlable(res.config))),
        age=res.age,
        constant_names=String.(res.constant_names),
        constants=res.constants,
        forcing_names=String.(res.forcing_names),
        time_series=res.time_series,
        co2=res.co2,
        o2=res.o2,
        temp=res.temp,
        status=res.status,
        prcout_co2=res.prcout_co2,
        prcout_temp=res.prcout_temp,
        sample_keys=res.sample_keys,
        n_simulated=res.n_simulated,
        n_evaluated=res.n_evaluated,
        has_covariances=res.covariances !== nothing,
        covariances=res.covariances === nothing ? zeros(0, 0, 0, 0) : res.covariances,
        provenance_keys=collect(keys(res.provenance)),
        provenance_values=collect(values(res.provenance)),
    )
    return path
end

"""
    load_result(path) -> PrecalibrationResult

Read a file written by [`save_result`](@ref).
"""
function load_result(path::AbstractString)
    isfile(path) || throw(ArgumentError("result file not found: $path"))
    d = JLD2.load(path)
    get(d, "format_version", 0) == 1 || throw(ArgumentError("$path: not a GeocarbPrecalibration result file"))
    cfg = try
        TOML.parse(d["config_toml"])
    catch err
        throw(ArgumentError("$path: the stored configuration (config_toml) cannot be parsed: $(sprint(showerror, err))"))
    end
    prov = Dict{String,String}(zip(d["provenance_keys"], d["provenance_values"]))
    return PrecalibrationResult(
        d["tag"],
        d["config_text"],
        cfg,
        d["age"],
        Symbol.(d["constant_names"]),
        d["constants"],
        Symbol.(d["forcing_names"]),
        d["time_series"],
        d["co2"],
        d["o2"],
        d["temp"],
        d["status"],
        d["prcout_co2"],
        d["prcout_temp"],
        d["sample_keys"],
        d["n_simulated"],
        get(d, "n_evaluated", d["n_simulated"]),     # files written before n_evaluated existed
        d["has_covariances"] ? d["covariances"] : nothing,
        prov,
    )
end

# Convert values to types TOML can store. TOML has no null, so `nothing` entries of a
# dictionary are omitted (the reader then uses the default). ±Inf and NaN are written
# as TOML's native inf/nan, so they read back as numbers.
function _tomlable(x::AbstractDict)
    out = Dict{String,Any}()
    for (k, v) in x
        v === nothing && continue
        out[String(k)] = _tomlable(v)
    end
    return out
end
_tomlable(x::AbstractVector) = [_tomlable(v) for v in x]
_tomlable(x::Tuple) = [_tomlable(v) for v in x]
_tomlable(x::Symbol) = String(x)
_tomlable(::Nothing) = throw(ArgumentError("`nothing` can only be stored as an omitted dictionary entry"))
_tomlable(x::AbstractFloat) = Float64(x)
_tomlable(x) = x

"""
    write_summary_csvs(dir, res::PrecalibrationResult) -> Vector{String}

Write human-readable CSV summaries next to the JLD2 file:
`constants.csv` (accepted constants, one row per sample), `prcout.csv` (% outbound,
sample keys) and `provenance.toml`. Returns the paths written.
"""
function write_summary_csvs(dir::AbstractString, res::PrecalibrationResult)
    mkpath(dir)
    p1 = write_csv(
        joinpath(dir, "constants.csv"),
        String.(res.constant_names),
        [res.constants[:, j] for j in axes(res.constants, 2)],
    )
    p2 = write_csv(
        joinpath(dir, "prcout.csv"),
        ["chunk", "index", "prcout_co2", "prcout_temp"],
        [res.sample_keys[:, 1], res.sample_keys[:, 2], res.prcout_co2, res.prcout_temp],
    )
    p3 = joinpath(dir, "provenance.toml")
    open(p3, "w") do io
        return TOML.print(
            io,
            Dict(
                "tag" => res.tag,
                "n_accepted" => n_accepted(res),
                "n_simulated" => res.n_simulated,
                "n_evaluated" => res.n_evaluated,
                "acceptance_rate" => acceptance_rate(res),
                "provenance" => res.provenance,
                "config" => _tomlable(res.config),
            ),
        )
    end
    return [p1, p2, p3]
end
