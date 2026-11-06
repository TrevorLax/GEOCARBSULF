# Shared helpers for the Julia side of the timing benchmark: job files, the raw CSV
# writer (schema of TIMING_BENCHMARK_PLAN.md §7), timers, correctness guards and paths.
#
# Every benchmark script is started by run_timing.jl as
#     julia --project=benchmark/timing <script> <job file>
# and appends one row per measurement to the raw CSV named in the job file.

using Dates: Dates
using Printf: @sprintf
using Random: Random
using Statistics: median, quantile

const HARNESS_DIR = normpath(joinpath(@__DIR__, ".."))
const REPO_DIR = normpath(joinpath(HARNESS_DIR, "..", ".."))

# ---------------------------------------------------------------------------------
# Job files: plain `key=value` lines, readable from R without extra packages.
# ---------------------------------------------------------------------------------

function read_job(path::AbstractString)
    d = Dict{String,String}()
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || startswith(s, "#")) && continue
        k, v = split(s, "="; limit = 2)
        d[strip(k)] = strip(v)
    end
    return d
end

function write_job(path::AbstractString, d::AbstractDict)
    mkpath(dirname(path))
    open(path, "w") do io
        for k in sort!(collect(keys(d)))
            v = d[k]
            s = v isa AbstractVector ? join(string.(v), ",") : string(v)
            occursin('\n', s) && error("job value for $k contains a newline")
            println(io, k, "=", s)
        end
    end
    return path
end

jstr(job, k, default = nothing) = haskey(job, k) ? job[k] : (default === nothing ? error("job file: missing key '$k'") : default)
jint(job, k, default = nothing) = parse(Int, replace(jstr(job, k, default === nothing ? nothing : string(default)), "_" => ""))
jfloat(job, k, default = nothing) = parse(Float64, jstr(job, k, default === nothing ? nothing : string(default)))
jbool(job, k, default = false) = lowercase(jstr(job, k, string(default))) in ("true", "1", "yes")
function jints(job, k)
    s = jstr(job, k, "")
    return isempty(s) ? Int[] : [parse(Int, replace(x, "_" => "")) for x in split(s, ",")]
end
jlist(job, k) = (s = jstr(job, k, ""); isempty(s) ? String[] : String.(split(s, ",")))

# ---------------------------------------------------------------------------------
# Raw CSV writer
# ---------------------------------------------------------------------------------

const RAW_HEADER = ["impl", "variant", "component", "subcomponent", "workload", "n", "threads", "rep", "mode",
                    "wall_s", "cpu_s", "gc_s", "compile_s", "alloc_bytes", "peak_rss_bytes", "checksum_ok",
                    "session_id", "timestamp", "notes"]

const PER_SAMPLE_HEADER = ["impl", "variant", "component", "rep", "sample", "group", "iterations", "n_failed",
                           "seconds", "session_id"]

struct RawWriter
    path::String
    per_sample_path::String
    session::String
    impl::String
    rep::Int
end

function RawWriter(job::AbstractDict)
    w = RawWriter(jstr(job, "raw_file"), jstr(job, "per_sample_file"), jstr(job, "session_id"), "julia",
                  jint(job, "rep", 1))
    for (p, h) in ((w.path, RAW_HEADER), (w.per_sample_path, PER_SAMPLE_HEADER))
        mkpath(dirname(p))
        isfile(p) || open(io -> println(io, join(h, ",")), p, "w")
    end
    return w
end

_csvfield(x::AbstractString) = (occursin(r"[\",\n]", x) ? "\"" * replace(x, "\"" => "\"\"") * "\"" : x)
_csvfield(x::Bool) = x ? "true" : "false"
_csvfield(x::AbstractFloat) = isnan(x) ? "NA" : @sprintf("%.9g", x)
_csvfield(x::Integer) = x < 0 ? "NA" : string(x)
_csvfield(x) = _csvfield(string(x))

"""
    record!(w; component, wall_s, ...)

Append one measurement. Unknown quantities are left as NA.
"""
function record!(w::RawWriter; variant::AbstractString, component::AbstractString, wall_s::Real,
                 subcomponent::AbstractString = "", workload::AbstractString = "", n::Integer = 1,
                 threads::Integer = Threads.nthreads(), rep::Integer = w.rep, mode::AbstractString = "warm",
                 cpu_s::Real = NaN, gc_s::Real = NaN, compile_s::Real = NaN, alloc_bytes::Integer = -1,
                 peak_rss_bytes::Integer = -1, checksum_ok::Bool = true, notes::AbstractString = "",
                 impl::AbstractString = w.impl)
    row = Any[impl, variant, component, subcomponent, workload, n, threads, rep, mode, Float64(wall_s),
              Float64(cpu_s), Float64(gc_s), Float64(compile_s), alloc_bytes, peak_rss_bytes, checksum_ok,
              w.session, Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS"), notes]
    open(io -> println(io, join(_csvfield.(row), ",")), w.path, "a")
    return nothing
end

"Record the result of [`measure`](@ref) (wall, GC, compile time, allocations)."
record!(w::RawWriter, m::NamedTuple; kwargs...) =
    record!(w; merge((wall_s = m.wall, gc_s = m.gc, compile_s = m.compile, alloc_bytes = m.bytes), values(kwargs))...)

function record_per_sample!(w::RawWriter, variant, component, sample::Integer, group, iterations, n_failed, seconds)
    open(w.per_sample_path, "a") do io
        println(io, join(_csvfield.(Any[w.impl, variant, component, w.rep, sample, group, iterations, n_failed,
                                       Float64(seconds), w.session]), ","))
    end
end

# ---------------------------------------------------------------------------------
# Timers
# ---------------------------------------------------------------------------------

"""
    measure(f) -> (wall, gc, compile, bytes, value)

Wall time (s), GC time (s), compilation time (s) and bytes allocated by one call of `f`.
"""
function measure(f)
    t = @timed f()
    compile = hasproperty(t, :compile_time) ? Float64(t.compile_time) : NaN
    return (wall = Float64(t.time), gc = Float64(t.gctime), compile = compile, bytes = Int(t.bytes), value = t.value)
end

"Wall time of `k` calls of `f()`, in seconds per call."
function per_call(f, k::Integer)
    t0 = time_ns()
    for _ in 1:k
        f()
    end
    return (time_ns() - t0) / 1e9 / k
end

"Number of calls needed for a timed block to last at least `target` seconds."
function calls_for(f; target::Real = 0.05, max_calls::Integer = 10^7)
    k = 1
    while k < max_calls
        t = per_call(f, k) * k
        t >= target && return k
        k = t <= 0 ? 10k : min(10k, ceil(Int, 1.2 * k * target / t))
    end
    return max_calls
end

peak_rss() = Int(Sys.maxrss())

# ---------------------------------------------------------------------------------
# Correctness guards (plan §6.7)
# ---------------------------------------------------------------------------------

struct GuardError <: Exception
    msg::String
end
Base.showerror(io::IO, e::GuardError) = print(io, "correctness guard failed: ", e.msg)

check(cond::Bool, msg::AbstractString) = cond || throw(GuardError(msg))

"""
    component!(f, w, variant, component; workload = "")

Run one benchmark component. A failed guard or an error is logged as a row with
`checksum_ok = false` (so the report shows it), printed, and does not stop the
other components.
"""
function component!(f, w::RawWriter, variant::AbstractString, component::AbstractString; workload::AbstractString = "")
    t0 = time()
    try
        f()
        @info @sprintf("%-6s %-10s %-14s done in %.1f s", w.impl, variant, component, time() - t0)
    catch err
        msg = err isa GuardError ? err.msg : sprint(showerror, err)
        @error "$(w.impl) $variant $component failed" exception = (err, catch_backtrace())
        record!(w; variant = variant, component = component, workload = workload, wall_s = NaN,
                checksum_ok = false, notes = first(replace(msg, '\n' => ' '), 300))
    end
    return nothing
end

"Inf/NaN positions identical; finite values within rtol before the first failure and rtol_post after."
function check_outputs(label, got::AbstractMatrix, ref::AbstractMatrix; rtol = 1e-8, rtol_post = 1e-4, atol = 1e-10,
                       exact::Bool = false)
    check(size(got) == size(ref), "$label: size $(size(got)) vs $(size(ref))")
    post = cumsum(isinf.(ref); dims = 2) .> 0
    nbad = 0; nmask = 0
    for i in eachindex(got, ref)
        x, y = got[i], ref[i]
        if isnan(x) || isnan(y) || isinf(x) || isinf(y)
            isequal(x, y) || (nmask += 1)
        elseif exact
            x == y || (nbad += 1)
        else
            tol = post[i] ? rtol_post : rtol
            abs(x - y) <= atol + tol * max(abs(x), abs(y)) || (nbad += 1)
        end
    end
    check(nmask == 0, "$label: $nmask Inf/NaN positions differ from the reference")
    check(nbad == 0, "$label: $nbad finite values outside tolerance" * (exact ? " (exact match required)" : ""))
    return true
end

# ---------------------------------------------------------------------------------
# Paths and environment
# ---------------------------------------------------------------------------------

const SYNC_MARKERS = ("proton drive", "onedrive", "dropbox", "google drive", "my drive", "icloud", "box sync", "pcloud")

"`true` if the path looks like it is inside a cloud-synced folder."
is_synced_path(p::AbstractString) = any(m -> occursin(m, lowercase(abspath(p))), SYNC_MARKERS)

function default_results_root()
    if Sys.iswindows()
        base = get(ENV, "LOCALAPPDATA", joinpath(homedir(), "AppData", "Local"))
        return joinpath(base, "GeocarbTiming")
    end
    return joinpath(get(ENV, "XDG_CACHE_HOME", joinpath(homedir(), ".cache")), "GeocarbTiming")
end

"Total physical memory in bytes."
total_memory() = Int(Sys.total_memory())

"""
    memory_ok(projected_bytes, fraction) -> Bool

The memory guard of plan §5.4: `false` if a run would need more than `fraction` of RAM.
"""
memory_ok(projected::Real, fraction::Real) = projected <= fraction * total_memory()

# Projected peak memory (bytes) of the precalibration engines, used by the guard.
#   R GlobalLHS: two n × 56 matrices (parameters_lhs and par_calib_tmp) plus the list of
#   chunks (finding F-11); per chunk 58·58·chunk·12 covariances plus 58·chunk·12 series.
r_engine_bytes(n, chunk) = 3 * 8.0 * n * 56 + 8.0 * chunk * 12 * (58 * 58 + 58) + 4e8
julia_engine_bytes(n, chunk; global_lhs = false, covariances = false, threads = 1) =
    (global_lhs ? 2 * 8.0 * n * 56 : 0.0) + threads * 8.0 * chunk * (56 + 12 * 58 + 3 * 58) +
    (covariances ? threads * 8.0 * chunk * 12 * 58 * 58 : 0.0) + 1.5e9

# ---------------------------------------------------------------------------------
# Legacy inputs: the exports of test/legacy_comparison (constants.csv, time_series.csv,
# legacy_co2.csv, ...). compare.jl provides the readers and the ccall wrappers.
# ---------------------------------------------------------------------------------

function include_legacy_helpers()
    f = joinpath(REPO_DIR, "test", "legacy_comparison", "compare.jl")
    isfile(f) || error("missing $f")
    Base.include(Main, f)
    return nothing
end

"""
    sample_groups(co2_ref) -> Vector{String}

Stratification of plan §5.1: `clean` (no failed step), `heavy` (the 10 % with the most
failed steps) and `partial` (the rest).
"""
function sample_groups(co2_ref::AbstractMatrix)
    nfail = vec(count(isinf, co2_ref; dims = 2))
    cut = quantile(Float64.(nfail), 0.9)
    return [nf == 0 ? "clean" : (nf >= cut && nf > 0) ? "heavy" : "partial" for nf in nfail], nfail
end

const SESSION_START = time()
