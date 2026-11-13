"""
    ExperimentConfig(; kwargs...)

Everything that defines one precalibration experiment. It is usually read from a
TOML file with [`load_experiments`](@ref); see `experiments/` and the
"Experiments" page of the documentation.

| field | default | meaning |
|:--|:--|:--|
| `name`, `description`, `tag` | | labels; `tag` names the output directory (`"ct_out30"` style) |
| `prior_file` | `data/GEOCARB_input_summaries_calib_all.csv` | parameter priors |
| `time_array_file` | `data/GEOCARB_input_arrays_NewDegassing.csv` | forcing centres and σ |
| `proxy_file` | Foster et al. (2017) compilation | CO2 proxies |
| `temperature_file` | `data/Mills_GR_2019_temp_co2.csv` | temperature windows |
| `variance_reduction_file` | `data/variance_reduction.toml` | inverse-Wishart dof factors |
| `use_godderis` | `true` | Goddéris et al. (2012) arrays for fA, fAw/fA, fD, GEOG |
| `proxies` | all five | proxy types assimilated |
| `constraint` | `:both` | `:co2`, `:temp` or `:both` |
| `threshold` | `0.5` | accept if % outbound ≤ threshold (for each constrained variable) |
| `reject_failed_runs` | `false` | reject runs with any failed step (fixes finding F-04; `false` = R behaviour) |
| `cretaceous_age` | `nothing` | if set, also require the temperature to be inside its window at this age |
| `run_on_time_centers` | `false` | run the model on the forcing *centres* instead of the sampled series (the R Cretaceous experiment, finding F-02) |
| `time_center_from` | `nothing` | path of an earlier result (`result.jld2`) whose mean accepted series become the new forcing centres |
| `n_sample`, `n_per_chunk`, `n_accept_min` | | maximum simulations, chunk size, stop after this many accepted |
| `seed` | `1234` | random seed (≥ 0) |
| `constant_design` | `:chunked_lhs` | `:chunked_lhs` or `:global_lhs` ([`ConstantDesign`](@ref)) |
| `time_sampler` | `:inverse_wishart` | `:inverse_wishart` or `:multivariate_t` ([`TimeSeriesSampler`](@ref)) |
| `save_covariances` | `false` | keep the inverse-Wishart covariance draws of accepted samples (large) |
| `nsig` | `1.0` | window half-width in standard deviations |
| `T0` | `15.0` | present-day temperature added to model temperatures |
| `model` | `ModelOptions()` | model options |
| `output_dir` | `"results"` | parent directory of the result directory `output_dir/tag` |
"""
Base.@kwdef struct ExperimentConfig
    name::String = "experiment"
    description::String = ""
    tag::String = ""
    index::Int = 1
    prior_file::String = datapath("GEOCARB_input_summaries_calib_all.csv")
    time_array_file::String = datapath("GEOCARB_input_arrays_NewDegassing.csv")
    proxy_file::String = datapath("CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv")
    temperature_file::String = datapath("Mills_GR_2019_temp_co2.csv")
    variance_reduction_file::String = datapath("variance_reduction.toml")
    use_godderis::Bool = true
    proxies::Vector{Symbol} = collect(Symbol, DEFAULT_PROXIES)
    constraint::Symbol = :both
    threshold::Float64 = 0.5
    reject_failed_runs::Bool = false
    cretaceous_age::Union{Nothing,Float64} = nothing
    run_on_time_centers::Bool = false
    time_center_from::Union{Nothing,String} = nothing
    n_sample::Int = 10_000
    n_per_chunk::Int = 1_000
    n_accept_min::Int = 10_000
    seed::Int = 1234
    constant_design::Symbol = :chunked_lhs
    time_sampler::Symbol = :inverse_wishart
    save_covariances::Bool = false
    nsig::Float64 = 1.0
    T0::Float64 = PRESENT_TEMPERATURE
    model::ModelOptions = ModelOptions()
    output_dir::String = "results"
    source::String = ""
end

"""
    validate(cfg::ExperimentConfig) -> cfg

Throw an `ArgumentError` describing the first problem found (missing files, an
inconsistent sample size, unknown choices, ...).
"""
function validate(cfg::ExperimentConfig)
    err(msg) = throw(ArgumentError("experiment '$(cfg.name)' ($(cfg.tag)): $msg"))
    for (k, f) in (
        ("prior_file", cfg.prior_file),
        ("time_array_file", cfg.time_array_file),
        ("proxy_file", cfg.proxy_file),
        ("temperature_file", cfg.temperature_file),
        ("variance_reduction_file", cfg.variance_reduction_file),
    )
        isfile(f) || err("$k not found: $f")
    end
    cfg.constraint in (:co2, :temp, :both) || err("constraint must be co2, temp or both (got $(cfg.constraint))")
    (0 < cfg.threshold <= 1) || err("threshold must be in (0, 1] (got $(cfg.threshold))")
    cfg.n_sample >= 1 || err("n_sample must be ≥ 1")
    cfg.n_per_chunk >= 1 || err("n_per_chunk must be ≥ 1")
    cfg.n_accept_min >= 1 || err("n_accept_min must be ≥ 1")
    cfg.seed >= 0 || err("seed must be ≥ 0")
    cfg.constant_design in (:chunked_lhs, :global_lhs) || err("constant_design must be chunked_lhs or global_lhs")
    cfg.time_sampler in (:inverse_wishart, :multivariate_t) ||
        err("time_sampler must be inverse_wishart or multivariate_t")
    if cfg.save_covariances && cfg.time_sampler != :inverse_wishart
        err("save_covariances requires time_sampler = inverse_wishart")
    end
    cfg.nsig > 0 || err("nsig must be positive")
    isfinite(cfg.T0) || err("T0 must be finite")
    if cfg.cretaceous_age !== nothing
        (0 <= cfg.cretaceous_age <= AGE_MAX) || err("cretaceous_age must be within [0, 570]")
    end
    isempty(cfg.proxies) && err("at least one proxy type is needed")
    validate(cfg.model)
    return cfg
end

# --- TOML loading -----------------------------------------------------------------

const _FSR_FILES = Dict(
    "DT2019" => "GEOCARB_input_arrays_NewDegassing.csv",
    "LENTON" => "GEOCARB_input_arrays_Lenton.csv",
    "PR2011" => "GEOCARB_input_arrays.csv",
)
const _DATA_FILES = Dict("F2017" => "CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv")

const _TOP_KEYS = Set([
    "name",
    "description",
    "tag_suffix",
    "param_choice",
    "data_choice",
    "fsr_choice",
    "data_dir",
    "prior_file",
    "time_array_file",
    "proxy_file",
    "temperature_file",
    "variance_reduction_file",
    "use_godderis",
    "proxies",
    "constraint",
    "threshold",
    "reject_failed_runs",
    "cretaceous_age",
    "run_on_time_centers",
    "time_center_from",
    "n_sample",
    "n_per_chunk",
    "n_accept_min",
    "seed",
    "constant_design",
    "time_sampler",
    "save_covariances",
    "nsig",
    "T0",
    "output_dir",
    "grid",
    "model",
])
const _GRID_KEYS = Set(["threshold", "constraint", "seeds", "seed_multiplier"])

function _constraint_symbol(x)
    s = lowercase(String(x))
    s in ("co2", "c") && return :co2
    s in ("temp", "t", "temperature") && return :temp
    s in ("both", "ct", "co2+temp") && return :both
    return throw(ArgumentError("unknown constraint '$x' (use co2, temp or both)"))
end

_constraint_code(c::Symbol) =
    if c == :co2
        "c"
    elseif c == :temp
        "t"
    else
        "ct"
    end

"""
    default_tag(constraint, threshold; suffix = "", seed = nothing) -> String

Result tag in the style of the R code: `"<c|t|ct>_out<percent>"`, for example
`"ct_out30"`, followed by `_<suffix>` and `_seed<seed>` when given.
"""
function default_tag(constraint::Symbol, threshold::Real; suffix::AbstractString="", seed=nothing)
    tag = _constraint_code(constraint) * "_out" * string(round(Int, 100 * threshold))
    isempty(suffix) || (tag *= "_" * suffix)
    seed === nothing || (tag *= "_seed$(seed)")
    return tag
end

function _resolve_data_file(d::AbstractDict, key::String, default_name::String, data_dir::String)
    f = haskey(d, key) ? String(d[key]) : default_name
    return isabspath(f) ? f : joinpath(data_dir, f)
end

"""
    load_experiments(path) -> Vector{ExperimentConfig}

Read an experiment TOML file. Without a `[grid]` table it describes one experiment.
With a `[grid]` table, one experiment is created for every combination of
`grid.constraint` (outer loop) and `grid.threshold` (inner loop), in that order, as
`expand.grid` did in `lhs_driver.R`. Seeds are then

- `seed_multiplier * index` with `index = 1, 2, …` (the R rule `1234*idx_experiment`), or
- one experiment per entry of `grid.seeds`, or
- the top-level `seed`.

Relative data-file names are resolved against `data_dir` (default: the package's
`data/` directory). `output_dir` and `time_center_from` are relative to the current
working directory.
"""
function load_experiments(path::AbstractString)
    text = read(path, String)
    d = TOML.parse(text)
    for k in keys(d)
        k in _TOP_KEYS ||
            throw(ArgumentError("$path: unknown key '$k'; allowed: " * join(sort!(collect(_TOP_KEYS)), ", ")))
    end
    data_dir = haskey(d, "data_dir") ? String(d["data_dir"]) : DATA_DIR
    isabspath(data_dir) || (data_dir = normpath(joinpath(dirname(abspath(path)), data_dir)))

    param_choice = String(get(d, "param_choice", "all"))
    fsr_choice = String(get(d, "fsr_choice", "DT2019"))
    data_choice = String(get(d, "data_choice", "F2017"))
    haskey(_FSR_FILES, fsr_choice) || throw(ArgumentError("$path: unknown fsr_choice '$fsr_choice'"))
    haskey(_DATA_FILES, data_choice) || throw(
        ArgumentError(
            "$path: data_choice '$data_choice' has no data file in this repository (finding F-14); use F2017 or set proxy_file",
        ),
    )

    files = (
        prior_file=_resolve_data_file(d, "prior_file", "GEOCARB_input_summaries_calib_$(param_choice).csv", data_dir),
        time_array_file=_resolve_data_file(d, "time_array_file", _FSR_FILES[fsr_choice], data_dir),
        proxy_file=_resolve_data_file(d, "proxy_file", _DATA_FILES[data_choice], data_dir),
        temperature_file=_resolve_data_file(d, "temperature_file", "Mills_GR_2019_temp_co2.csv", data_dir),
        variance_reduction_file=_resolve_data_file(d, "variance_reduction_file", "variance_reduction.toml", data_dir),
    )
    model = haskey(d, "model") ? model_options_from_dict(d["model"]) : ModelOptions()
    suffix = String(get(d, "tag_suffix", ""))

    base = Dict{Symbol,Any}(
        :name => String(get(d, "name", splitext(basename(path))[1])),
        :description => String(get(d, "description", "")),
        :use_godderis => Bool(get(d, "use_godderis", true)),
        :proxies => Symbol.(get(d, "proxies", collect(String.(DEFAULT_PROXIES)))),
        :reject_failed_runs => Bool(get(d, "reject_failed_runs", false)),
        :cretaceous_age => haskey(d, "cretaceous_age") ? Float64(d["cretaceous_age"]) : nothing,
        :run_on_time_centers => Bool(get(d, "run_on_time_centers", false)),
        :time_center_from => haskey(d, "time_center_from") ? String(d["time_center_from"]) : nothing,
        :n_sample => Int(get(d, "n_sample", 10_000)),
        :n_per_chunk => Int(get(d, "n_per_chunk", 1_000)),
        :n_accept_min => Int(get(d, "n_accept_min", 10_000)),
        :constant_design => Symbol(get(d, "constant_design", "chunked_lhs")),
        :time_sampler => Symbol(get(d, "time_sampler", "inverse_wishart")),
        :save_covariances => Bool(get(d, "save_covariances", false)),
        :nsig => Float64(get(d, "nsig", 1.0)),
        :T0 => Float64(get(d, "T0", PRESENT_TEMPERATURE)),
        :output_dir => String(get(d, "output_dir", "results")),
        :model => model,
        :source => text,
    )
    for (k, v) in pairs(files)
        base[k] = v
    end

    base_constraint = _constraint_symbol(get(d, "constraint", "both"))
    base_threshold = Float64(get(d, "threshold", 0.5))
    base_seed = Int(get(d, "seed", 1234))

    configs = ExperimentConfig[]
    if !haskey(d, "grid")
        tag = default_tag(base_constraint, base_threshold; suffix=suffix)
        push!(
            configs,
            ExperimentConfig(;
                base..., constraint=base_constraint, threshold=base_threshold, seed=base_seed, tag=tag, index=1
            ),
        )
    else
        g = d["grid"]
        for k in keys(g)
            k in _GRID_KEYS || throw(
                ArgumentError("$path: unknown [grid] key '$k'; allowed: " * join(sort!(collect(_GRID_KEYS)), ", "))
            )
        end
        thresholds = Float64.(get(g, "threshold", [base_threshold]))
        constraints = _constraint_symbol.(get(g, "constraint", [String(base_constraint)]))
        seeds = haskey(g, "seeds") ? Int.(g["seeds"]) : nothing
        mult = haskey(g, "seed_multiplier") ? Int(g["seed_multiplier"]) : nothing
        (seeds !== nothing && mult !== nothing) &&
            throw(ArgumentError("$path: [grid] may set seeds or seed_multiplier, not both"))
        index = 0
        for c in constraints, th in thresholds
            for s in (seeds === nothing ? (nothing,) : seeds)
                index += 1
                seed = if s !== nothing
                    s
                elseif mult !== nothing
                    mult * index
                else
                    base_seed
                end
                tag = default_tag(c, th; suffix=suffix, seed=s)
                push!(configs, ExperimentConfig(; base..., constraint=c, threshold=th, seed=seed, tag=tag, index=index))
            end
        end
    end
    return configs
end

"""
    config_summary(cfg::ExperimentConfig) -> Dict{String,Any}

TOML-friendly summary of a configuration (stored as provenance with every result).
"""
function config_summary(cfg::ExperimentConfig)
    d = Dict{String,Any}()
    for f in fieldnames(ExperimentConfig)
        f == :source && continue
        v = getfield(cfg, f)
        d[String(f)] = if v === nothing
            "none"
        elseif v isa ModelOptions
            options_dict(v)
        elseif v isa Symbol
            String(v)
        elseif v isa AbstractVector{Symbol}
            String.(v)
        else
            v
        end
    end
    return d
end

"""
    with_overrides(cfg::ExperimentConfig; kwargs...) -> ExperimentConfig

Copy of `cfg` with some fields replaced, for example
`with_overrides(cfg; n_sample = 1000, n_per_chunk = 100)`.
"""
function with_overrides(cfg::ExperimentConfig; kwargs...)
    d = Dict{Symbol,Any}(f => getfield(cfg, f) for f in fieldnames(ExperimentConfig))
    for (k, v) in kwargs
        k in fieldnames(ExperimentConfig) || throw(ArgumentError("unknown ExperimentConfig field :$k"))
        d[k] = v
    end
    return ExperimentConfig(; d...)
end
