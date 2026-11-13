#!/usr/bin/env julia
# collect.jl: turn the raw CSVs of one session into timings.csv, report.md and figures
# (plan §8).   julia --project=benchmark/timing benchmark/timing/collect.jl <results dir>

include(joinpath(@__DIR__, "lib", "common.jl"))
using Printf: @sprintf
using Statistics: mean
using TOML: TOML
using Random: Xoshiro

dir = ARGS[1]
isdir(joinpath(dir, "raw")) || error("$dir has no raw/ folder")

# ---------------------------------------------------------------------------------
# reading
# ---------------------------------------------------------------------------------

function parse_csv_line(line)
    out = String[]
    buf = IOBuffer()
    inq = false
    i = 1
    chars = collect(line)
    while i <= length(chars)
        c = chars[i]
        if inq
            if c == '"'
                if i < length(chars) && chars[i + 1] == '"'
                    write(buf, '"')
                    i += 1
                else
                    inq = false
                end
            else
                write(buf, c)
            end
        elseif c == '"'
            inq = true
        elseif c == ','
            push!(out, String(take!(buf)))
        else
            write(buf, c)
        end
        i += 1
    end
    push!(out, String(take!(buf)))
    return out
end

function read_rows(path)
    lines = filter(!isempty, readlines(path))
    isempty(lines) && return Dict{String,String}[]
    h = parse_csv_line(lines[1])
    rows = Dict{String,String}[]
    for l in lines[2:end]
        f = parse_csv_line(l)
        length(f) == length(h) || continue
        push!(rows, Dict(zip(h, f)))
    end
    return rows
end

num(x) = (x == "NA" || isempty(x)) ? NaN : something(tryparse(Float64, x), NaN)

rawfiles = filter(f -> endswith(f, ".csv") && !endswith(f, "_per_sample.csv"), readdir(joinpath(dir, "raw"); join=true))
rows = reduce(vcat, [read_rows(f) for f in rawfiles]; init=Dict{String,String}[])
psfiles = filter(f -> endswith(f, "_per_sample.csv"), readdir(joinpath(dir, "raw"); join=true))
ps = reduce(vcat, [read_rows(f) for f in psfiles]; init=Dict{String,String}[])
env = isfile(joinpath(dir, "env.toml")) ? TOML.parsefile(joinpath(dir, "env.toml")) : Dict{String,Any}()
sess = isfile(joinpath(dir, "session.toml")) ? TOML.parsefile(joinpath(dir, "session.toml")) : Dict{String,Any}()

# ---------------------------------------------------------------------------------
# statistics
# ---------------------------------------------------------------------------------

key(r) = (r["impl"], r["variant"], r["component"], r["subcomponent"], r["workload"], r["mode"])
groups = Dict{NTuple{6,String},Vector{Float64}}()
for r in rows
    r["checksum_ok"] == "true" || continue
    v = num(r["wall_s"])
    isnan(v) && continue
    push!(get!(groups, key(r), Float64[]), v)
end
q(v, p) = quantile(v, p)
function summary(v)
    isempty(v) && return (n=0, median=NaN, q25=NaN, q75=NaN, min=NaN)
    return (n=length(v), median=median(v), q25=q(v, 0.25), q75=q(v, 0.75), min=minimum(v))
end
open(joinpath(dir, "timings.csv"), "w") do io
    println(io, "impl,variant,component,subcomponent,workload,mode,reps,median_s,q25_s,q75_s,min_s")
    for k in sort!(collect(keys(groups)))
        s = summary(groups[k])
        println(io, join(_csvfield.(Any[k..., s.n, s.median, s.q25, s.q75, s.min]), ","))
    end
end

"Values of all rows matching the filters (strings or regexes); `mode` defaults to warm."
function vals(; impl, variant, component, sub, workload=nothing, mode="warm")
    m(x, f) = f === nothing || (f isa Regex ? occursin(f, x) : x == f)
    out = Float64[]
    for (k, v) in groups
        (
            m(k[1], impl) &&
            m(k[2], variant) &&
            m(k[3], component) &&
            m(k[4], sub) &&
            m(k[5], workload) &&
            m(k[6], mode)
        ) && append!(out, v)
    end
    return out
end

function boot_ratio(a, b; nboot=2000)
    (length(a) < 2 || length(b) < 2) && return (NaN, NaN)
    rng = Xoshiro(1)
    r = [median(rand(rng, a, length(a))) / median(rand(rng, b, length(b))) for _ in 1:nboot]
    return (quantile(r, 0.025), quantile(r, 0.975))
end

function fmt_t(x)
    return if isnan(x)
        "–"
    elseif x >= 100
        @sprintf("%.0f s", x)
    elseif x >= 1
        @sprintf("%.2f s", x)
    elseif x >= 1e-3
        @sprintf("%.2f ms", 1e3x)
    elseif x >= 1e-6
        @sprintf("%.2f µs", 1e6x)
    else
        @sprintf("%.1f ns", 1e9x)
    end
end
fmt_r(x) =
    if isnan(x)
        "–"
    elseif x >= 10
        @sprintf("%.0f×", x)
    else
        @sprintf("%.2f×", x)
    end
fmt_iqr(v) = isempty(v) ? "" : "[$(fmt_t(q(v, 0.25))), $(fmt_t(q(v, 0.75)))]"

"Fortran baseline: the shipped library if it was measured, otherwise the r_default build."
function fortran_base()
    for v in ("H0_shipped", "H0_r_default")
        x = vals(; impl="fortran", variant=v, component="M1", sub="ccall run_geocarb_")
        isempty(x) || return (v, x)
    end
    return ("–", Float64[])
end

workloads(component) = sort!(unique([k[5] for k in keys(groups) if k[3] == component]))

# ---------------------------------------------------------------------------------
# comparisons
# ---------------------------------------------------------------------------------

out = IOBuffer()
p(x...) = println(out, x...)
comparisons = Any[]    # (label, R/F vector, J vector, unit note)

function compare!(label, a, b; note="")
    (isempty(a) || isempty(b)) && return nothing
    return push!(comparisons, (label, a, b, note))
end

# M1: pure compute
for lib in ("shipped", "r_default")
    compare!(
        "M1 model call, Fortran ($lib, ccall) / Julia run_geocarb!",
        vals(; impl="fortran", variant="H0_$lib", component="M1", sub="ccall run_geocarb_"),
        vals(; impl="julia", variant="J", component="M1", sub="run_geocarb!");
        note="per call; >1× means Julia is faster",
    )
end
compare!(
    "M2 R model_run() / Julia run_geocarb (allocating)",
    vals(; impl="R", variant="R0", component="M2", sub="model_run"),
    vals(; impl="julia", variant="J", component="M2", sub="run_geocarb (allocating)");
    note="per call",
)
for wl in workloads("M3")
    compare!(
        "M3 supplemental '$wl', R model_run_supp() / Julia",
        vals(; impl="R", variant="R0", component="M3", sub="model_run_supp", workload=wl),
        vals(; impl="julia", variant="J", component="M3", sub="run_geocarb! + ModelOptions", workload=wl);
        note="per call",
    )
end
for wl in workloads("P1")
    compare!(
        "P1 LHS $wl",
        vals(; impl="R", variant="R0", component="P1", sub="randomLHS", workload=wl),
        vals(; impl="julia", variant="J", component="P1", sub="random_lhs", workload=wl),
    )
    compare!(
        "P2 constant transform $wl",
        vals(; impl="R", variant="R0", component="P2", sub=r"^rescale", workload=wl),
        vals(; impl="julia", variant="J", component="P2", sub="transform_unit", workload=wl),
    )
end
compare!(
    "P3 time series per sample, R / Julia inverse Wishart",
    vals(; impl="R", variant="R0", component="P3", sub="total (inverse Wishart + MvNormal)"),
    vals(; impl="julia", variant="J", component="P3", sub="total (inverse Wishart + MvNormal)");
    note="per sample, 12 forcings",
)
compare!(
    "P3 time series per sample, R / Julia multivariate t",
    vals(; impl="R", variant="R0", component="P3", sub="total (inverse Wishart + MvNormal)"),
    vals(; impl="julia", variant="J", component="P3", sub="total, multivariate t");
    note="per sample",
)
compare!(
    "P3 normalisation per sample",
    vals(; impl="R", variant="R0", component="P3", sub="normalisation"),
    vals(; impl="julia", variant="J", component="P3", sub="normalisation"),
)
for wl in workloads("P4")
    compare!(
        "P4 store covariances $wl",
        vals(; impl="R", variant="R0", component="P4", sub="store accepted (abind)", workload=wl),
        vals(; impl="julia", variant="J", component="P4", sub="store accepted (append + permutedims)", workload=wl);
        note="per sample",
    )
end
compare!(
    "P5 normal draws, rnorm / randn (StableRNG)",
    vals(; impl="R", variant="R0", component="P5", sub="rnorm"),
    vals(; impl="julia", variant="J", component="P5", sub="randn StableRNG");
    note="per draw",
)
compare!(
    "C1 % outbound per series",
    vals(; impl="R", variant="R0", component="C1", sub="percout"),
    vals(; impl="julia", variant="J", component="C1", sub="legacy_percent_outbound"),
)
compare!(
    "C2 acceptance per sample",
    vals(; impl="R", variant="R0", component="C2", sub=r"^which"),
    vals(; impl="julia", variant="J", component="C2", sub=r"^accepts");
    note="Julia also computes both % outbound here",
)
function r_e2(wl)
    v = vals(; impl="R", variant="R0", component="E2", sub="lhs_sampling.R (original)", workload=wl)
    return if isempty(v)
        vals(; impl="R", variant="R0", component="E2", sub="lhs_sampling.R (instrumented copy)", workload=wl)
    else
        v
    end
end
for wl in workloads("E2"), jv in ("J1", "J0", "J2", "J3")
    compare!(
        "E2 precalibration $wl, R0 / $jv",
        r_e2(wl),
        vals(; impl="julia", variant=jv, component="E2", sub="run_precalibration", workload=wl),
    )
end
for wl in workloads("E2")
    compare!(
        "E2 precalibration $wl, R0 / R1 (Fortran $(get(get(sess, "config", Dict()), "general", Dict("r1_variant" => "O3"))["r1_variant"]))",
        r_e2(wl),
        vals(; impl="R", variant="R1", component="E2", sub=r"^lhs_sampling.R", workload=wl),
    )
end
for wl in workloads("E3"), jv in ("J1", "J2", "J3")
    compare!(
        "E3 realistic $wl, R0 / $jv",
        vals(; impl="R", variant="R0", component="E3", sub=r"", workload=wl),
        vals(; impl="julia", variant=jv, component="E3", sub="run_precalibration", workload=wl),
    )
end
compare!(
    "S1 cold start, process + packages",
    vals(; impl="R", variant="R0", component="S1", sub="process + packages + dyn.load", mode="cold"),
    vals(; impl="julia", variant="J", component="S1", sub="process + using GeocarbPrecalibration", mode="cold");
    note="<1× means R starts faster",
)
compare!(
    "G1 first figure, fresh process",
    vals(; impl="R", variant="R0", component="G1", sub=r"fresh process", mode="cold"),
    vals(; impl="julia", variant="J", component="G1", sub=r"fresh process", mode="cold"),
)
asecs = sort!(unique([k[4] for k in keys(groups) if k[1] == "R" && occursin(r"^A\d", k[4])]))
for sname in asecs
    compare!(
        "$sname",
        vals(; impl="R", variant="R0", component=r"^A", sub=sname),
        vals(; impl="julia", variant="J", component=r"^A", sub=sname);
        note="warm; shared ensemble",
    )
end
gnames = sort!(unique([k[4] for k in keys(groups) if k[1] == "R" && k[3] == "G2"]))
for gname in gnames
    jb = vals(; impl="julia", variant="J", component="G2", sub="$(gname): build")
    jw = vals(; impl="julia", variant="J", component="G2", sub="$(gname): write file")
    n = min(length(jb), length(jw))
    compare!(
        "$gname",
        vals(; impl="R", variant="R0", component="G2", sub=gname),
        jb[1:n] .+ jw[1:n];
        note="warm; build + write",
    )
end
for s1 in ("save() covariances", "save() parameters", "save() model")
    compare!(
        "O1 $s1 / Julia save_result (with covariances)",
        vals(; impl="R", variant="R0", component="O1", sub=s1),
        vals(; impl="julia", variant="J0", component="O1", sub="save_result (JLD2)");
        note="R saves three files; compare the sum",
    )
end
for jv in ("J1", "J2", "J3")
    compare!(
        "X1 end to end (whole process), R0 / $jv",
        vals(; impl="R", variant="R0", component="X1", sub="whole process", mode="cold"),
        vals(; impl="julia", variant=jv, component="X1", sub="whole process", mode="cold"),
    )
end

# ---------------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------------

p("# Timing benchmark report: R/Fortran vs Julia")
p()
p(
    "Session `",
    basename(dir),
    "`, suite `",
    get(sess, "suite", "?"),
    "`, ",
    get(sess, "reps", "?"),
    " repetition(s). ",
    "Plan: `TIMING_BENCHMARK_PLAN.md`. Raw data: `raw/`; aggregated: `timings.csv`.",
)
p()
p("## Machine")
p()
p("| item | value |\n|:--|:--|")
for k in (
    "host",
    "os_build",
    "cpu_model",
    "physical_cores",
    "logical_cores",
    "ram_bytes",
    "julia_version",
    "power_scheme",
    "on_battery",
    "disk_of_results",
    "results_root_synced",
    "repo_synced",
    "gfortran_used_by_R_CMD_SHLIB",
    "gfortran_on_path",
    "gfortran_version",
    "r_fflags",
    "r_fcflags",
)
    v = get(env, k, "–")
    v = k == "ram_bytes" && v isa Integer ? @sprintf("%.1f GB", v / 1e9) : replace(string(v), '\n' => " ", '|' => "/")
    p("| ", k, " | ", first(v, 160), " |")
end
av = get(env, "antivirus", Dict())
p("| antivirus | ", replace(string(get(av, "products", "–")), '\n' => "; "), " |")
p("| antivirus policy | ", get(av, "policy", "–"), " |")
p()
rsi = get(env, "r_session_info", "")
m_blas = match(r"BLAS: *([^\n]*)", rsi)
p(
    "R BLAS: `",
    m_blas === nothing ? "unknown" : strip(m_blas.captures[1]),
    "`. Julia BLAS: `",
    get(env, "blas_config", "–"),
    "`.",
)
p()

# guards
bad = [r for r in rows if r["checksum_ok"] != "true"]
p("## Correctness guards")
p()
if isempty(bad)
    p("All guards passed (", length(rows), " rows).")
else
    p("**", length(bad), " row(s) failed a correctness guard or errored; their timings are excluded:**")
    p()
    for r in bad
        p("- ", r["impl"], " ", r["variant"], " ", r["component"], " ", r["workload"], ": ", r["notes"])
    end
end
# a wall time that is neither a number nor NA means the writer shuffled the columns of the row
malformed = [r for r in rows if !(r["wall_s"] in ("NA", "")) && tryparse(Float64, r["wall_s"]) === nothing]
if !isempty(malformed)
    p()
    p(
        "**",
        length(malformed),
        " malformed row(s) (wall time not a number; columns probably shifted by the writer) are excluded:**",
    )
    p()
    for r in malformed
        p(
            "- ",
            r["impl"],
            " ",
            r["variant"],
            " ",
            r["component"],
            ": subcomponent `",
            r["subcomponent"],
            "`, wall_s `",
            r["wall_s"],
            "`",
        )
    end
end
b3 = [r for r in rows if r["component"] == "B3" && r["checksum_ok"] == "true" && !isnan(num(r["wall_s"]))]
if !isempty(b3)
    p()
    p(
        "Instrumented R copies (B3): results identical to the original code; timer overhead ",
        join(
            [
                @sprintf("%+.1f %%", 100num(r["wall_s"])) * " (" * r["subcomponent"] * ", " * r["workload"] * ")" for
                r in b3
            ],
            "; ",
        ),
        ".",
    )
end
p()

# sentinels
p("## Drift sentinels")
p()
sent = [r for r in rows if r["component"] == "SENT"]
flagged = false
for impl in unique(r["impl"] for r in sent), sub in unique(r["subcomponent"] for r in sent if r["impl"] == impl)
    v = [num(r["wall_s"]) for r in sent if r["impl"] == impl && r["subcomponent"] == sub]
    isempty(v) && continue
    drift = maximum(v) / minimum(v) - 1
    global flagged |= drift > 0.05
    p(
        "- ",
        impl,
        " ",
        sub,
        ": ",
        join(fmt_t.(v), " → "),
        @sprintf(" (spread %.1f %%)", 100drift),
        drift > 0.05 ? " **> 5 %: session flagged**" : "",
    )
end
isempty(sent) && p("No sentinel rows.")
flagged && p("\n**Timing drift above 5 % during the session; treat small differences with caution.**")
p()

p("## Summary: R (or Fortran) vs Julia")
p()
p(
    "Ratio = median(R or Fortran) / median(Julia): above 1× Julia is faster. 95 % bootstrap interval over repetitions ",
    "(– with fewer than two repetitions).",
)
p()
p("| comparison | R / Fortran median | Julia median | ratio | 95 % CI | note |\n|:--|--:|--:|--:|:--|:--|")
for (label, a, b, note) in comparisons
    lo, hi = boot_ratio(a, b)
    p(
        "| ",
        label,
        " | ",
        fmt_t(median(a)),
        " | ",
        fmt_t(median(b)),
        " | ",
        fmt_r(median(a) / median(b)),
        " | ",
        isnan(lo) ? "–" : "$(fmt_r(lo)) – $(fmt_r(hi))",
        " | ",
        note,
        " |",
    )
end
p()

# E1 breakdown
function breakdown(impl, variant, wl)
    d = Dict{String,Float64}()
    for (k, v) in groups
        (k[1] == impl && k[2] == variant && k[3] == "E1" && k[5] == wl && k[6] == "warm") || continue
        d[k[4]] = median(v)
    end
    return d
end
cat_r = Dict(
    "setup: time_series_df.R" => "setup",
    "lhs.R setup" => "setup",
    "lhs.R first_model_run" => "setup",
    "lhs.R constraints" => "setup",
    "lhs.R bounds" => "setup",
    "constants: LHS" => "constants",
    "constants: transform" => "constants",
    "constants: split into chunks" => "constants",
    "init" => "orchestration",
    "time series: allocate" => "time series",
    "time series: inverse Wishart" => "time series",
    "time series: MvNormal" => "time series",
    "time series: normalise" => "time series",
    "time series: loop overhead" => "time series",
    "model: allocate" => "model",
    "model" => "model",
    "model: loop overhead" => "model",
    "model: store outputs" => "orchestration",
    "percent outbound" => "constraints",
    "acceptance" => "constraints",
    "store accepted (rbind/abind)" => "store accepted",
    "orchestration (chunk loop minus blocks)" => "orchestration",
)
cat_j = Dict(
    "prepare" => "setup",
    "constants: LHS" => "constants",
    "constants: transform" => "constants",
    "constants: assemble" => "constants",
    "time series" => "time series",
    "model" => "model",
    "acceptance" => "constraints",
    "store accepted" => "store accepted",
    "chunk output" => "store accepted",
    "assemble" => "store accepted",
    "orchestration (not in a section)" => "orchestration",
    "checkpoint save" => "orchestration",
    "checkpoint load" => "orchestration",
)
cats = ["setup", "constants", "time series", "model", "constraints", "store accepted", "orchestration"]
common_wl = intersect(
    Set(k[5] for k in keys(groups) if k[1] == "R" && k[3] == "E1"),
    Set(k[5] for k in keys(groups) if k[1] == "julia" && k[3] == "E1"),
)
e1 = Dict{String,Any}()
if !isempty(common_wl)
    wl = last(sort!(collect(common_wl); by=w -> something(tryparse(Int, match(r"n=(\d+)", w).captures[1]), 0)))
    p("## Where the time goes in the precalibration engine (E1), ", wl)
    p()
    rows_e1 = Tuple{String,Dict{String,Float64}}[]
    for (impl, v, cmap) in (("R", "R0", cat_r), ("julia", "J1", cat_j), ("julia", "J0", cat_j))
        b = breakdown(impl, v, wl)
        isempty(b) && continue
        agg = Dict(c => 0.0 for c in cats)
        for (k, t) in b
            agg[get(cmap, k, "orchestration")] += t
        end
        push!(rows_e1, ("$impl $v", agg))
        e1["$impl $v"] = agg
    end
    p("| category | ", join(first.(rows_e1), " | "), " |\n|:--|", repeat("--:|", length(rows_e1)))
    for c in cats
        p(
            "| ",
            c,
            " | ",
            join([@sprintf("%s (%.0f %%)", fmt_t(a[c]), 100a[c] / sum(values(a))) for (_, a) in rows_e1], " | "),
            " |",
        )
    end
    p("| **total** | ", join([fmt_t(sum(values(a))) for (_, a) in rows_e1], " | "), " |")
    p()
    p(
        "R: timers of the generated `lhs_sampling_timed.R` and `lhs_timed.R`; Julia: `@timeit_debug` sections of ",
        "`run_precalibration` (single thread). 'orchestration' is the chunk loop minus the timed blocks.",
    )
    p()
end

# M4 per sample
if !isempty(ps)
    p("## Model cost per sample (M4)")
    p()
    p("| implementation | clean | partial | heavy | prior mean | all |\n|:--|--:|--:|--:|--:|--:|")
    impls = unique((r["impl"], r["variant"]) for r in ps if r["component"] == "M4")
    for (im, va) in impls
        sel = [r for r in ps if r["impl"] == im && r["variant"] == va && r["component"] == "M4"]
        g(gr) = (v=[num(r["seconds"]) for r in sel if r["group"] == gr]; isempty(v) ? "–" : fmt_t(median(v)))
        p(
            "| ",
            im,
            " ",
            va,
            " | ",
            g("clean"),
            " | ",
            g("partial"),
            " | ",
            g("heavy"),
            " | ",
            g("prior_mean"),
            " | ",
            fmt_t(median([num(r["seconds"]) for r in sel])),
            " |",
        )
    end
    p()
    p(
        "Median seconds per model call by group (plan §5.1: clean = no failed step, heavy = the 10 % with most failed steps). ",
        "Julia's Newton-iteration counts are attached to every row in `raw/*_per_sample.csv`.",
    )
    p()
end

# R layer decomposition
lay = [(l, vals(; impl="R", variant="R0", component="M2", sub=l)) for l in ("bare", "run_geocarbF", "model_run")]
base_name, ccall_v = fortran_base()
if all(!isempty(v) for (_, v) in lay) && !isempty(ccall_v)
    c0 = median(ccall_v)
    p("## R overhead per model call (M1/M2)")
    p()
    p("| layer | median per call | above the Fortran compute |\n|:--|--:|--:|")
    p("| Fortran compute (ccall from Julia, ", base_name, ") | ", fmt_t(c0), " | – |")
    for (l, v) in lay
        p(
            "| R ",
            if l == "bare"
                ".Fortran() on prepared arguments"
            elseif l == "run_geocarbF"
                "run_geocarbF()"
            else
                "model_run()"
            end,
            " | ",
            fmt_t(median(v)),
            " | ",
            fmt_t(median(v) - c0),
            " |",
        )
    end
    p()
end

# Fortran variants
fv = sort!(unique([k[2] for k in keys(groups) if k[1] == "fortran" && k[3] == "M1" && k[4] == "ccall run_geocarb_"]))
if length(fv) > 1
    p("## Fortran build variants (M6, H0)")
    p()
    p("| library | median per call | relative to the first |\n|:--|--:|--:|")
    base = median(vals(; impl="fortran", variant=fv[1], component="M1", sub="ccall run_geocarb_"))
    for v in fv
        t = median(vals(; impl="fortran", variant=v, component="M1", sub="ccall run_geocarb_"))
        p("| ", v, " | ", fmt_t(t), " | ", fmt_r(t / base), " |")
    end
    p()
end

# scaling
for (comp, title) in (("P1", "LHS design"), ("P2", "constant transform"), ("E2", "precalibration, fixed work"))
    ks = sort!(unique([(k[1], k[2], k[4]) for k in keys(groups) if k[3] == comp]))
    isempty(ks) && continue
    p("### Scaling: ", title, " (", comp, ")")
    p()
    p("| implementation | ", join(workloads(comp), " | "), " |\n|:--|", repeat("--:|", length(workloads(comp))))
    for (im, va, sub) in ks
        p(
            "| ",
            im,
            " ",
            va,
            " ",
            sub,
            " | ",
            join(
                [
                    (v=get(groups, (im, va, comp, sub, wl, "warm"), Float64[]); isempty(v) ? "–" : fmt_t(median(v))) for
                    wl in workloads(comp)
                ],
                " | ",
            ),
            " |",
        )
    end
    p()
end

# threads
e4 = [r for r in rows if r["component"] == "E4" && r["checksum_ok"] == "true"]
if !isempty(e4)
    p("## Thread scaling (E4)")
    p()
    fps = unique([match(r"fingerprint=(\w+)", r["notes"]).captures[1] for r in e4])
    p(
        if length(fps) == 1
            "Results bit-identical for every thread count (fingerprint `$(fps[1])`)."
        else
            "**Results differ between thread counts: fingerprints $(join(fps, ", ")).**"
        end,
    )
    p()
    p("| threads | median | speed-up | efficiency |\n|--:|--:|--:|--:|")
    byt = Dict{Int,Vector{Float64}}()
    for r in e4
        push!(get!(byt, parse(Int, r["threads"]), Float64[]), num(r["wall_s"]))
    end
    t1 = haskey(byt, 1) ? median(byt[1]) : NaN
    for t in sort!(collect(keys(byt)))
        m = median(byt[t])
        p(
            "| ",
            t,
            " | ",
            fmt_t(m),
            " | ",
            fmt_r(t1 / m),
            " | ",
            isnan(t1) ? "–" : @sprintf("%.0f %%", 100t1 / m / t),
            " |",
        )
    end
    p()
end

# checkpoints
e6 = sort!([k for k in keys(groups) if k[3] == "E6"])
if !isempty(e6)
    p("## Checkpoints (E6, Julia J1)")
    p()
    p("| run | workload | median |\n|:--|:--|--:|")
    for k in e6
        p("| ", k[4], " | ", k[5], " | ", fmt_t(median(groups[k])), " |")
    end
    p()
end

# memory
e5 = [r for r in rows if r["component"] == "E5"]
if !isempty(e5)
    p("## Peak memory (E5)")
    p()
    p("| implementation | configuration | peak RSS | note |\n|:--|:--|--:|:--|")
    for r in e5
        pk = num(r["peak_rss_bytes"])
        p(
            "| ",
            r["impl"],
            " ",
            r["variant"],
            " | ",
            r["workload"],
            " | ",
            isnan(pk) ? "–" : @sprintf("%.2f GB", pk / 1e9),
            " | ",
            r["notes"],
            " |",
        )
    end
    p()
    p(
        "Extrapolation to 20 million samples: fit peak = a + b·n per configuration (needs at least two sizes; only ",
        "meaningful when the sizes differ by 10× or more, as in the standard and full suites).",
    )
    for cfgname in unique(replace(r["workload"], r"n=\d+ " => "") for r in e5)
        pts = [
            (parse(Int, match(r"n=(\d+)", r["workload"]).captures[1]), num(r["peak_rss_bytes"])) for
            r in e5 if replace(r["workload"], r"n=\d+ " => "") == cfgname && !isnan(num(r["peak_rss_bytes"]))
        ]
        length(unique(first.(pts))) >= 2 || continue
        maximum(first.(pts)) >= 10 * minimum(first.(pts)) || continue
        x = Float64.(first.(pts))
        y = last.(pts)
        b = sum((x .- mean(x)) .* (y .- mean(y))) / sum((x .- mean(x)) .^ 2)
        a = mean(y) - b * mean(x)
        p("- ", cfgname, @sprintf(": %.2f GB per 10⁶ samples → %.1f GB at 2·10⁷", b * 1e6 / 1e9, (a + b * 2e7) / 1e9))
    end
    p()
end

# cold start
p("## Cold start (S1, S0, G1, S1b) and first calls (S2, S3)")
p()
p("| implementation | measurement | mode | median | IQR |\n|:--|:--|:--|--:|:--|")
for k in sort!([k for k in keys(groups) if k[3] in ("S0", "S1", "S1b", "S2", "S3", "G1")])
    v = groups[k]
    p("| ", k[1], " ", k[2], " | ", k[3], " ", k[4], " | ", k[6], " | ", fmt_t(median(v)), " | ", fmt_iqr(v), " |")
end
p()
p(
    "Antivirus real-time scanning is left on (decision T6, option A), so cold-start and file-writing times include it. ",
    "It may weigh more on Julia, which loads more binary files at start-up; this report does not separate that cost.",
)
p()

# figures
g3 = [r for r in rows if r["component"] == "G3"]
if !isempty(g3)
    p("## Figures (G2 per figure in the summary; G3 file sizes)")
    p()
    p("| implementation | figure | size |\n|:--|:--|--:|")
    for (im, sub) in sort!(unique([(r["impl"], r["subcomponent"]) for r in g3]))
        v = [num(r["alloc_bytes"]) for r in g3 if r["impl"] == im && r["subcomponent"] == sub]
        p("| ", im, " | ", sub, " | ", @sprintf("%.0f kB", median(v) / 1e3), " |")
    end
    p()
    p("R-only figures (no Makie function yet): deltaT2X_samplesize, co2_and_uncertainties.")
    p()
end

# analysis numbers cross-check
nf = isdir(joinpath(dir, "numbers")) ? readdir(joinpath(dir, "numbers"); join=true) : String[]
rn = filter(f -> occursin("R_numbers", f), nf);
jn = filter(f -> occursin("julia_numbers", f), nf);
if !isempty(rn) && !isempty(jn)
    function rd(f)
        return Dict(
            replace(
                r["quantity"], r"_q(.*)$" => s -> "_q" * string(parse(Float64, match(r"_q(.*)$", s).captures[1]))
            ) => num(r["value"]) for r in read_rows(f)
        )
    end
    a = rd(rn[1])
    b = rd(jn[1])
    ks = intersect(keys(a), keys(b))
    worst = isempty(ks) ? NaN : maximum(abs(a[k] - b[k]) / max(abs(a[k]), 1e-300) for k in ks)
    p("## Analysis cross-check")
    p()
    p(
        "ΔT2x quantiles of the c_out30 experiment on the shared ensemble, R vs Julia: largest relative difference ",
        @sprintf("%.1e", worst),
        worst <= 1e-12 ? " (identical up to rounding)." : " — **differs; check the analysis code**.",
    )
    p()
end

# end to end
x1 = sort!([k for k in keys(groups) if k[3] == "X1"])
if !isempty(x1)
    p("## End to end (X1)")
    p()
    p("| implementation | stage | median |\n|:--|:--|--:|")
    for k in x1
        p("| ", k[1], " ", k[2], " | ", k[4], " | ", fmt_t(median(groups[k])), " |")
    end
    p()
end

# projection
e2r = Dict{Int,Float64}();
e2j = Dict{String,Dict{Int,Float64}}();
for (k, v) in groups
    k[3] == "E2" || continue
    m = match(r"n=(\d+)", k[5])
    m === nothing && continue
    n = parse(Int, m.captures[1])
    if k[1] == "R" && k[2] == "R0"
        e2r[n] = median(v) / n
    elseif k[1] == "julia" && k[4] == "run_precalibration"
        get!(e2j, k[2], Dict{Int,Float64}())[n] = median(v) / n
    end
end
if !isempty(e2r) || !isempty(e2j)
    p("## Projection to the paper workflow (X4)")
    p()
    p(
        "Seconds per simulation at the largest measured fixed-work size, times the number of simulations. The main ",
        "grid has 15 experiments plus 2 extra seeds, each allowed up to 2·10⁷ simulations (`experiments/main/grid.toml`); ",
        "how many are actually needed depends on each experiment's acceptance rate, so both a per-10⁶ figure and the upper ",
        "bound are given.",
    )
    p()
    p("| implementation | s per simulation | per 10⁶ simulations | upper bound, 17 × 2·10⁷ |\n|:--|--:|--:|--:|")
    for (name, d) in vcat(isempty(e2r) ? [] : [("R0", e2r)], [(k, v) for (k, v) in sort!(collect(e2j); by=first)])
        nmax = maximum(keys(d))
        c = d[nmax]
        p(
            "| ",
            name,
            " | ",
            fmt_t(c),
            " | ",
            @sprintf("%.1f h", c * 1e6 / 3600),
            " | ",
            @sprintf("%.0f days", c * 17 * 2e7 / 86400),
            " |",
        )
    end
    p()
end

# hypotheses
p("## Hypotheses (plan §9)")
p()
med(v) = isempty(v) ? NaN : median(v)
h1 = med(vals(; impl="julia", variant="J", component="M1", sub="run_geocarb!")) / med(fortran_base()[2])
h2 = med(vals(; impl="R", variant="R0", component="M2", sub="model_run")) / med(fortran_base()[2])
share(a, c) = (a === nothing || !haskey(a, c)) ? NaN : a[c] / sum(values(a))
hr = [
    (
        "H1",
        "Julia model within 0.5–2× of the Fortran",
        if isnan(h1)
            "not measured"
        else
            @sprintf("Julia/Fortran = %.2f → %s", h1, 0.5 <= h1 <= 2 ? "holds" : "does not hold")
        end,
    ),
    (
        "H2",
        "R model_run() costs several (≥ 3) times the Fortran compute",
        isnan(h2) ? "not measured" : @sprintf("model_run/compute = %.1f → %s", h2, h2 >= 3 ? "holds" : "does not hold"),
    ),
    (
        "H3",
        "time series is the largest share of R0 and J1 precalibration",
        if isempty(e1)
            "not measured"
        else
            join(
                [
                    "$k: time series $(round(Int, 100share(a, "time series"))) %, model $(round(Int, 100share(a, "model"))) %"
                    for (k, a) in e1
                ],
                "; ",
            )
        end,
    ),
]
mt = med(vals(; impl="julia", variant="J", component="P3", sub="total, multivariate t"))
mm = med(vals(; impl="julia", variant="J", component="M1", sub="run_geocarb!"))
push!(
    hr,
    (
        "H3b",
        "with the multivariate-t sampler (J3) the model becomes the largest share",
        if isnan(mt) || isnan(mm)
            "not measured"
        else
            @sprintf(
                "model %s vs multivariate-t sampler %s per sample → %s",
                fmt_t(mm),
                fmt_t(mt),
                mm > mt ? "holds" : "does not hold"
            )
        end,
    ),
)
o3 = med(vals(; impl="fortran", variant="H0_O3", component="M1", sub="ccall run_geocarb_"))
o2 = med(vals(; impl="fortran", variant="H0_r_default", component="M1", sub="ccall run_geocarb_"))
oo = med(vals(; impl="fortran", variant="H0_O0", component="M1", sub="ccall run_geocarb_"))
push!(
    hr,
    (
        "H4",
        "-O3 matters little for R0 but is visible in H0",
        if isnan(o3) || isnan(o2)
            "not measured (run a suite with fortran_variants = true)"
        else
            @sprintf("same compiler: -O3 / R default (-O2) = %.2f; -O0 / R default = %.2f", o3 / o2, oo / o2)
        end,
    ),
)
sj = med(vals(; impl="julia", variant="J", component="S1", sub="process + using GeocarbPrecalibration", mode="cold"))
sr = med(vals(; impl="R", variant="R0", component="S1", sub="process + packages + dyn.load", mode="cold"))
per_r = isempty(e2r) ? NaN : e2r[maximum(keys(e2r))]
per_j = haskey(e2j, "J1") ? e2j["J1"][maximum(keys(e2j["J1"]))] : NaN
s0j = med(vals(; impl="julia", variant="J", component="S0", sub=r"probe process", mode="cold"))
s0r = med(vals(; impl="R", variant="R0", component="S0", sub=r"probe process", mode="cold"))
be = (s0j - s0r) / (per_r - per_j)
push!(
    hr,
    (
        "H5",
        "Julia's cold start exceeds R's; break-even within 10³–10⁴ samples",
        if isnan(sj) || isnan(sr)
            "not measured"
        else
            @sprintf(
                "process + packages: R %s, Julia %s; to the first model result (S0): R %s, Julia %s; break-even ≈ %s samples of fixed-work precalibration (J1 vs R0; compiling the engine itself adds to it, see X1)",
                fmt_t(sr),
                fmt_t(sj),
                fmt_t(s0r),
                fmt_t(s0j),
                if isnan(be)
                    "–"
                elseif be <= 0
                    "0"
                else
                    @sprintf("%.0f", be)
                end
            )
        end,
    ),
)
push!(
    hr,
    (
        "H6",
        "GlobalLHS memory ~0.9 GB per 10⁶ rows; ChunkedLHS flat",
        isempty(e5) ? "not measured" : "see 'Peak memory'",
    ),
)
push!(
    hr,
    (
        "H7",
        "thread efficiency ≥ 80 % up to the physical core count",
        isempty(e4) ? "not measured" : "see 'Thread scaling'",
    ),
)
m5 = [
    (r["subcomponent"], num(r["wall_s"])) for
    r in rows if r["component"] == "M5" && r["checksum_ok"] == "true" && !startswith(r["subcomponent"], "Float32")
]
if !isempty(m5)
    d = Dict{String,Vector{Float64}}()
    for (k, v) in m5
        push!(get!(d, k, Float64[]), v)
    end
    base = median(get(d, "single_literals=true corrected_derivative=false", [NaN]))
    spread = maximum(abs(median(v) / base - 1) for v in values(d))
    push!(
        hr,
        (
            "H8",
            "model options change runtime by < 2 %",
            @sprintf("largest change %.1f %% → %s", 100spread, spread < 0.02 ? "holds" : "does not hold"),
        ),
    )
end
p("| # | prediction | result |\n|:--|:--|:--|")
for (a, b, c) in hr
    p("| ", a, " | ", b, " | ", c, " |")
end
p()

p("## Caveats")
p()
p(
    "- The shared ensemble of the analysis benchmark is generated by the Julia port (CO2 + temperature, threshold ",
    "0.5), because the paper's .RData outputs are not in the repository; R reads it as .RData, so both sides analyse ",
    "identical samples. Every experiment tag reads the same ensemble.",
)
p(
    "- The realistic runs (E3) and the end-to-end run (X1) use the 50 % threshold: at 30 % no prior draw of the ",
    "1000-sample legacy comparison is accepted, and R would need hours per run.",
)
p(
    "- The supplemental and Cretaceous parts of analysis_and_plots.R are excluded on both sides; X2 and X3 are not ",
    "implemented yet.",
)
p("- G1 is measured without a PrecompileTools workload and without a sysimage (plan §3.8 lists those as variants).")
p("- S1b compiles GeocarbPrecalibration only; its dependencies are compiled once per Julia depot.")
haskey(env, "r_packages") &&
    occursin("bench NOT INSTALLED", env["r_packages"]) &&
    p(
        "- The R package `bench` is not installed: R timings use proc.time() (lower resolution) and the R per-sample model timings are coarse.",
    )
p()
p("_Generated by benchmark/timing/collect.jl on ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM"), "._")

report = String(take!(out))
write(joinpath(dir, "report.md"), report)
println("wrote ", joinpath(dir, "report.md"), " and timings.csv")

# ---------------------------------------------------------------------------------
# figures (optional)
# ---------------------------------------------------------------------------------
try
    @eval using CairoMakie
    figdir = mkpath(joinpath(dir, "report_figures"))
    if !isempty(e1)
        names_ = collect(keys(e1))
        fig = Figure(; size=(700, 380))
        ax = Axis(
            fig[1, 1];
            xticks=(1:length(names_), names_),
            ylabel="share of precalibration time",
            title="E1: where the time goes",
        )
        for (i, n) in enumerate(names_)
            tot = sum(values(e1[n]))
            bottom = 0.0
            for (j, c) in enumerate(cats)
                h = e1[n][c] / tot
                barplot!(ax, [i], [h]; offset=bottom, color=Makie.wong_colors()[mod1(j, 7)], label=i == 1 ? c : nothing)
                bottom += h
            end
        end
        Legend(fig[1, 2], ax)
        save(joinpath(figdir, "e1_breakdown.png"), fig)
    end
    if !isempty(ps)
        fig = Figure(; size=(700, 420))
        ax = Axis(
            fig[1, 1];
            xlabel="Newton iterations (total over 58 steps)",
            ylabel="seconds per call",
            yscale=log10,
            title="M4: model cost per sample",
        )
        for (j, (im, va)) in enumerate(
            unique((r["impl"], r["variant"]) for r in ps if r["component"] == "M4" && r["iterations"] != "NA")
        )
            sel = [
                r for
                r in ps if r["impl"] == im && r["variant"] == va && r["component"] == "M4" && r["iterations"] != "NA"
            ]
            scatter!(
                ax,
                [num(r["iterations"]) for r in sel],
                [max(num(r["seconds"]), 1e-9) for r in sel];
                markersize=3,
                color=(Makie.wong_colors()[mod1(j, 7)], 0.5),
                label="$im $va",
            )
        end
        axislegend(ax; position=:rb)
        save(joinpath(figdir, "m4_per_sample.png"), fig)
    end
    println("figures in ", figdir)
catch err
    println("figures skipped: ", sprint(showerror, err))
end
