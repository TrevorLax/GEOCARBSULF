# Checkpoints of the precalibration engine.
#
# Every finished chunk can be written to a checkpoint directory and reused when a run
# is restarted. A chunk is only valid for the configuration that produced it, so the
# directory carries a manifest (`checkpoint_manifest.toml`) describing that
# configuration, and every chunk file stores the same fingerprint. Resuming with a
# different configuration is an error instead of silently mixing samples.
#
# Files are written to a temporary name and then renamed, so a crash mid-write cannot
# leave a truncated chunk under its final name.

const CHECKPOINT_MANIFEST = "checkpoint_manifest.toml"

# Fields of the configuration that do not change the content of any chunk.
#  - name, description, tag, index, output_dir, overrides: labels only;
#  - n_accept_min: only decides how many chunks are consumed, so a run can be resumed
#    with a larger target;
#  - the input-file paths: their content is compared through SHA-256 hashes instead, so
#    a project that was moved or synced to another machine can still resume.
const _CHECKPOINT_IGNORED_FIELDS = (
    "name",
    "description",
    "tag",
    "index",
    "output_dir",
    "overrides",
    "n_accept_min",
    "prior_file",
    "time_array_file",
    "proxy_file",
    "temperature_file",
    "variance_reduction_file",
    "time_center_from",
)

"""
    checkpoint_manifest(cfg::ExperimentConfig) -> Dict{String,Any}

Description of everything that determines the content of the chunks of `cfg`: a
copy of the configuration summary and its SHA-256, SHA-256 hashes of the input files
and the package version. Labels (`name`, `tag`, `output_dir`, …), `n_accept_min` and
the input-file *paths* are left out: inputs are compared by content, so a moved project
can resume. Written to
`checkpoint_manifest.toml` in a checkpoint directory and compared on resume.
"""
function checkpoint_manifest(cfg::ExperimentConfig)
    summary = config_summary(cfg)
    for k in _CHECKPOINT_IGNORED_FIELDS
        delete!(summary, k)
    end
    inputs = Dict{String,Any}()
    for (k, f) in (
        ("prior_file", cfg.prior_file),
        ("time_array_file", cfg.time_array_file),
        ("proxy_file", cfg.proxy_file),
        ("temperature_file", cfg.temperature_file),
        ("variance_reduction_file", cfg.variance_reduction_file),
        ("time_center_from", cfg.time_center_from),
    )
        f === nothing && continue
        inputs[k] = _file_sha256(f)
    end
    m = Dict{String,Any}(
        "package_version" => string(something(pkgversion(@__MODULE__), "unknown")),
        "config" => _tomlable(summary),
        "config_sha256" => bytes2hex(SHA.sha256(_canonical_toml(summary))),
        "inputs_sha256" => inputs,
    )
    m["fingerprint"] = bytes2hex(SHA.sha256(_canonical_toml(m)))
    return m
end

_file_sha256(path::AbstractString) = isfile(path) ? bytes2hex(open(SHA.sha256, path)) : "missing"
_canonical_toml(d::AbstractDict) = sprint(io -> TOML.print(io, _tomlable(d); sorted=true))

# Flatten a manifest to "a.b" => value pairs, for readable error messages.
function _flatten(d::AbstractDict, prefix::String="")
    out = Dict{String,Any}()
    for (k, v) in d
        key = isempty(prefix) ? String(k) : prefix * "." * String(k)
        if v isa AbstractDict
            merge!(out, _flatten(v, key))
        else
            out[key] = v
        end
    end
    return out
end

"""
    prepare_checkpoint_dir(dir, cfg) -> fingerprint::String

Create `dir` if needed and make sure its checkpoints belong to `cfg`:

- a new or empty directory gets a manifest;
- a directory with a matching manifest is reused;
- a directory whose manifest differs, or that holds chunk files but no manifest
  (written before manifests existed), raises an `ArgumentError` naming the differences.
"""
function prepare_checkpoint_dir(dir::AbstractString, cfg::ExperimentConfig)
    mkpath(dir)
    want = checkpoint_manifest(cfg)
    path = joinpath(dir, CHECKPOINT_MANIFEST)
    if isfile(path)
        have = TOML.parsefile(path)
        if get(have, "fingerprint", nothing) != want["fingerprint"]
            a = _flatten(have)
            b = _flatten(want)
            diff = sort!([
                k for k in union(keys(a), keys(b)) if
                !(k in ("fingerprint", "config_sha256")) && get(a, k, nothing) != get(b, k, nothing)
            ])
            throw(
                ArgumentError(
                    "checkpoint directory $dir was written by a different configuration " *
                    "(differs in: $(join(diff, ", "))). Use another checkpoint directory or delete this one.",
                ),
            )
        end
    else
        stale = filter(f -> occursin(r"^chunk_\d+\.jld2$", f), readdir(dir))
        isempty(stale) || throw(
            ArgumentError(
                "checkpoint directory $dir holds $(length(stale)) chunk file(s) but no $CHECKPOINT_MANIFEST, so " *
                "the configuration that wrote them is unknown. Use another checkpoint directory or delete them.",
            ),
        )
        _atomic_write(path) do io
            return TOML.print(io, _tomlable(want); sorted=true)
        end
    end
    return want["fingerprint"]
end

# Write through a temporary file in the same directory, then rename it into place.
function _atomic_write(f::Function, path::AbstractString)
    tmp = path * ".tmp"
    try
        open(f, tmp, "w")
        mv(tmp, path; force=true)
    catch
        rm(tmp; force=true)
        rethrow()
    end
    return path
end
