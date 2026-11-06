# The precalibration engine: one function replaces lhs_sampling.R, lhs_sampling_supp.R
# and lhs_sampling_cret.R.

# Everything a chunk needs; read-only, so it can be shared between threads.
struct PrecalibrationSetup
    cfg::ExperimentConfig
    priors::Vector{TruncatedPrior}
    calib_index::Vector{Int}          # canonical position of each calibrated constant
    base_values::Vector{Float64}      # all 56 constants at their means (fixed ones stay)
    sampler::TimeSeriesSampler
    center::TimeForcings{Float64}
    ctx::EvaluationContext
    rule::AcceptanceRule
    U_global::Union{Nothing,Matrix{Float64}}
end

struct ChunkOutput
    chunk::Int
    n::Int
    idx::Vector{Int}
    constants::Matrix{Float64}
    series::Array{Float64,3}
    co2::Matrix{Float64}
    o2::Matrix{Float64}
    temp::Matrix{Float64}
    status::Matrix{UInt8}
    prcout_co2::Vector{Float64}
    prcout_temp::Vector{Float64}
    covariances::Union{Nothing,Array{Float64,4}}
end

# Deterministic per-chunk seed: results do not depend on how chunks are scheduled.
_chunk_seed(seed::Integer, c::Integer) = UInt64(seed) * 0x9e3779b97f4a7c15 + UInt64(c)

_n_chunks(cfg::ExperimentConfig) = cld(cfg.n_sample, cfg.n_per_chunk)
_chunk_size(cfg::ExperimentConfig, c::Integer) =
    c < _n_chunks(cfg) ? cfg.n_per_chunk : cfg.n_sample - (_n_chunks(cfg) - 1) * cfg.n_per_chunk

"""
    prepare_precalibration(cfg::ExperimentConfig) -> PrecalibrationSetup

Read all inputs and build the priors, samplers, windows and acceptance rule of an
experiment. Called by [`run_precalibration`](@ref); exposed for inspection and tests.
"""
function prepare_precalibration(cfg::ExperimentConfig)
    validate(cfg)
    table = read_prior_table(cfg.prior_file)
    priors = build_priors(table)
    calib_index = [findfirst(==(p.name), CONSTANT_PARAMETER_NAMES) for p in priors]
    base_values = parameter_vector(mean_constants(table))

    tprior = read_time_arrays(cfg.time_array_file; use_godderis = cfg.use_godderis)
    center = tprior.center
    if cfg.time_center_from !== nothing
        prev = load_result(cfg.time_center_from)
        n_accepted(prev) >= 1 || throw(ArgumentError("time_center_from: $(cfg.time_center_from) has no accepted samples"))
        prev.age == center.age || throw(ArgumentError("time_center_from: age grids differ"))
        center = mean_time_forcings(prev.time_series, prev.age)
    end
    fvr = read_variance_reduction(cfg.variance_reduction_file)
    sampler = cfg.time_sampler == :inverse_wishart ?
        InverseWishartSampler(center, tprior.sigma, fvr) :
        MultivariateTSampler(center, tprior.sigma, fvr)

    proxy = read_proxy_data(cfg.proxy_file; proxies = cfg.proxies)
    tdata = read_temperature_data(cfg.temperature_file)
    ctx = EvaluationContext(co2_windows(proxy, center.age; nsig = cfg.nsig),
                            temperature_windows(tdata, center.age; nsig = cfg.nsig); T0 = cfg.T0)
    rule = build_rule(cfg)
    if cfg.cretaceous_age !== nothing
        any(==(cfg.cretaceous_age), center.age) ||
            throw(ArgumentError("cretaceous_age = $(cfg.cretaceous_age) is not on the model age grid"))
    end

    U_global = nothing
    if cfg.constant_design == :global_lhs
        gb = 8 * cfg.n_sample * length(priors) / 2^30
        gb > 2 && @warn "constant_design = global_lhs allocates $(round(gb; digits = 1)) GiB up front (finding F-11)"
        U_global = random_lhs(StableRNG(_chunk_seed(cfg.seed, 0)), cfg.n_sample, length(priors))
    end
    cfg.run_on_time_centers && @warn "run_on_time_centers = true: the model runs on the forcing centres; " *
        "the saved time series are sampled but did not influence acceptance (as in the R Cretaceous experiment, finding F-02)"
    return PrecalibrationSetup(cfg, priors, calib_index, base_values, sampler, center, ctx, rule, U_global)
end

function _run_chunk(setup::PrecalibrationSetup, c::Int)
    cfg = setup.cfg
    nc = _chunk_size(cfg, c)
    rng = StableRNG(_chunk_seed(cfg.seed, c))
    U = @timeit_debug TIMER "constants: LHS" begin
        if setup.U_global === nothing
            random_lhs(rng, nc, length(setup.priors))
        else
            first_row = (c - 1) * cfg.n_per_chunk + 1
            setup.U_global[first_row:(first_row + nc - 1), :]
        end
    end
    X = @timeit_debug TIMER "constants: transform" transform_unit(U, setup.priors)

    age = setup.center.age
    nt = length(age)
    buf = copy(setup.center)
    out = GeocarbResult{Float64}(age)
    vals = copy(setup.base_values)
    cov = cfg.save_covariances ? Dict{Symbol,Matrix{Float64}}() : nothing

    idx = Int[]
    cbuf = Float64[]; sbuf = Float64[]; co2buf = Float64[]; o2buf = Float64[]; tbuf = Float64[]
    stbuf = UInt8[]; pc_acc = Float64[]; pt_acc = Float64[]; covbuf = Float64[]

    for j in 1:nc
        @timeit_debug TIMER "time series" sample_time_forcings!(rng, buf, setup.sampler; covariances = cov)
        p = @timeit_debug TIMER "constants: assemble" begin
            for (q, ci) in enumerate(setup.calib_index)
                vals[ci] = X[j, q]
            end
            _constants_from_vector(Float64, vals)
        end
        @timeit_debug TIMER "model" run_geocarb!(out, p, cfg.run_on_time_centers ? setup.center : buf; options = cfg.model)
        ok = @timeit_debug TIMER "acceptance" accepts(setup.rule, out, setup.ctx)
        ok && @timeit_debug TIMER "store accepted" begin
            push!(idx, j)
            append!(cbuf, vals)
            for n in TIME_FORCING_NAMES
                append!(sbuf, getfield(buf, n))
                cov === nothing || append!(covbuf, vec(cov[n]))
            end
            append!(co2buf, out.co2); append!(o2buf, out.o2); append!(tbuf, out.temp)
            append!(stbuf, UInt8.(out.status))
            push!(pc_acc, legacy_percent_outbound(out.co2, setup.ctx.co2_windows))
            push!(pt_acc, _legacy_percent_outbound_shifted(out.temp, setup.ctx.T0, setup.ctx.temp_windows))
        end
    end

    @timeit_debug TIMER "chunk output" _chunk_output(c, nc, idx, cbuf, sbuf, co2buf, o2buf, tbuf, stbuf, pc_acc, pt_acc,
                                                       covbuf, cov !== nothing, nt)
end

function _chunk_output(c, nc, idx, cbuf, sbuf, co2buf, o2buf, tbuf, stbuf, pc_acc, pt_acc, covbuf, has_cov, nt)
    na = length(idx)
    constants = permutedims(reshape(cbuf, N_CONSTANTS, na))
    series = permutedims(reshape(sbuf, nt, N_FORCINGS, na), (1, 3, 2))
    covs = has_cov ? permutedims(reshape(covbuf, nt, nt, N_FORCINGS, na), (1, 2, 4, 3)) : nothing
    return ChunkOutput(c, nc, idx, constants, series, reshape(co2buf, nt, na), reshape(o2buf, nt, na),
        reshape(tbuf, nt, na), reshape(stbuf, nt, na), pc_acc, pt_acc, covs)
end

_chunk_file(dir::AbstractString, c::Integer) = joinpath(dir, @sprintf("chunk_%06d.jld2", c))

function _save_chunk(path::AbstractString, o::ChunkOutput)
    JLD2.jldsave(path; chunk = o.chunk, n = o.n, idx = o.idx, constants = o.constants, series = o.series,
        co2 = o.co2, o2 = o.o2, temp = o.temp, status = o.status, prcout_co2 = o.prcout_co2,
        prcout_temp = o.prcout_temp, has_cov = o.covariances !== nothing,
        covariances = o.covariances === nothing ? zeros(0, 0, 0, 0) : o.covariances)
    return path
end

function _load_chunk(path::AbstractString)
    d = JLD2.load(path)
    return ChunkOutput(d["chunk"], d["n"], d["idx"], d["constants"], d["series"], d["co2"], d["o2"],
        d["temp"], d["status"], d["prcout_co2"], d["prcout_temp"], d["has_cov"] ? d["covariances"] : nothing)
end

function _compute_or_load_chunk(setup::PrecalibrationSetup, c::Int, checkpoint_dir)
    if checkpoint_dir !== nothing
        f = _chunk_file(checkpoint_dir, c)
        isfile(f) && return @timeit_debug TIMER "checkpoint load" _load_chunk(f)
        o = _run_chunk(setup, c)
        @timeit_debug TIMER "checkpoint save" _save_chunk(f, o)
        return o
    end
    return _run_chunk(setup, c)
end

"""
    run_precalibration(cfg::ExperimentConfig; max_parallel = Threads.nthreads(),
                       checkpoint_dir = nothing, verbose = true) -> PrecalibrationResult

Run one precalibration experiment:

1. read the priors, forcing arrays, proxy data and temperature data;
2. in chunks of `cfg.n_per_chunk`, sample constants (Latin hypercube through the
   truncated priors) and forcing series, run the model, and keep the samples that pass
   the acceptance rule;
3. stop once `cfg.n_accept_min` samples are accepted (keeping exactly that many) or
   after `cfg.n_sample` simulations.

Chunks are independent: chunk `c` uses its own `StableRNG` seeded from `(cfg.seed, c)`.
Up to `max_parallel` chunks run at the same time on separate threads, and their results
are consumed in chunk order, so **the result does not depend on the number of
threads**. With `checkpoint_dir`, every finished chunk is written there and reused if
the run is restarted.
"""
function run_precalibration(cfg::ExperimentConfig; max_parallel::Integer = Threads.nthreads(),
                            checkpoint_dir::Union{Nothing,AbstractString} = nothing, verbose::Bool = true)
    t_start = time()
    started = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
    setup = @timeit_debug TIMER "prepare" prepare_precalibration(cfg)
    checkpoint_dir === nothing || mkpath(checkpoint_dir)
    nchunk = _n_chunks(cfg)
    nbatch = max(1, min(Int(max_parallel), nchunk))

    consumed = ChunkOutput[]
    n_simulated = 0
    n_acc = 0
    done = false
    c = 1
    while c <= nchunk && !done
        batch = c:min(c + nbatch - 1, nchunk)
        outs = if nbatch == 1
            [_compute_or_load_chunk(setup, k, checkpoint_dir) for k in batch]
        else
            tasks = [Threads.@spawn _compute_or_load_chunk(setup, k, checkpoint_dir) for k in batch]
            fetch.(tasks)
        end
        for o in outs
            n_simulated += o.n
            push!(consumed, o)
            n_acc += length(o.idx)
            if n_acc >= cfg.n_accept_min
                done = true
                break
            end
        end
        verbose && @info "precalibration $(cfg.tag): chunks 1:$(last(consumed).chunk) of $nchunk, " *
                         "$n_simulated simulated, $(min(n_acc, cfg.n_accept_min)) accepted"
        c = last(batch) + 1
    end

    res = @timeit_debug TIMER "assemble" _assemble(setup, consumed, n_simulated)
    res.provenance["started"] = started
    res.provenance["finished"] = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
    res.provenance["wall_seconds"] = @sprintf("%.1f", time() - t_start)
    res.provenance["max_parallel"] = string(nbatch)
    return res
end

function _assemble(setup::PrecalibrationSetup, outs::Vector{ChunkOutput}, n_simulated::Int)
    cfg = setup.cfg
    nt = length(setup.center.age)
    keep = cfg.n_accept_min
    parts = Tuple{ChunkOutput,UnitRange{Int}}[]
    total = 0
    for o in outs
        k = min(length(o.idx), keep - total)
        k > 0 && push!(parts, (o, 1:k))
        total += max(k, 0)
        total >= keep && break
    end
    cat3(f, dims) = isempty(parts) ? nothing : cat((f(o, r) for (o, r) in parts)...; dims = dims)
    constants = isempty(parts) ? zeros(0, N_CONSTANTS) : reduce(vcat, [o.constants[r, :] for (o, r) in parts])
    series = isempty(parts) ? zeros(nt, 0, N_FORCINGS) : cat3((o, r) -> o.series[:, r, :], 2)
    co2 = isempty(parts) ? zeros(nt, 0) : reduce(hcat, [o.co2[:, r] for (o, r) in parts])
    o2 = isempty(parts) ? zeros(nt, 0) : reduce(hcat, [o.o2[:, r] for (o, r) in parts])
    temp = isempty(parts) ? zeros(nt, 0) : reduce(hcat, [o.temp[:, r] for (o, r) in parts])
    status = isempty(parts) ? zeros(UInt8, nt, 0) : reduce(hcat, [o.status[:, r] for (o, r) in parts])
    pc = isempty(parts) ? Float64[] : reduce(vcat, [o.prcout_co2[r] for (o, r) in parts])
    pt = isempty(parts) ? Float64[] : reduce(vcat, [o.prcout_temp[r] for (o, r) in parts])
    keys_ = isempty(parts) ? zeros(Int, 0, 2) :
        reduce(vcat, [hcat(fill(o.chunk, length(r)), o.idx[r]) for (o, r) in parts])
    covs = nothing
    if cfg.save_covariances
        covs = isempty(parts) ? zeros(nt, nt, 0, N_FORCINGS) : cat3((o, r) -> o.covariances[:, :, r, :], 3)
    end
    total == 0 && @warn "precalibration $(cfg.tag): no simulation was accepted"

    prov = Dict{String,String}(
        "package_version" => string(something(pkgversion(@__MODULE__), "unknown")),
        "julia_version" => string(VERSION),
        "git_commit" => _git_commit(),
        "threads" => string(Threads.nthreads()),
        "n_chunks_consumed" => string(length(outs)),
    )
    return PrecalibrationResult(cfg.tag, cfg.source, config_summary(cfg), copy(setup.center.age),
        collect(CONSTANT_PARAMETER_NAMES), constants, collect(TIME_FORCING_NAMES), series, co2, o2, temp,
        status, pc, pt, keys_, n_simulated, covs, prov)
end

function _git_commit()
    try
        dir = normpath(joinpath(@__DIR__, "..", ".."))
        isdir(joinpath(dir, ".git")) || return "unknown"
        return readchomp(pipeline(`git -C $dir rev-parse HEAD`; stderr = devnull))
    catch
        return "unknown"
    end
end
