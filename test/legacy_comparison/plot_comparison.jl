#!/usr/bin/env julia
#
# Figures of the comparison between the Julia port and the original R/Fortran code.
#
#   julia --project=. test/legacy_comparison/plot_comparison.jl [DIR]
#
# DIR is the output folder of run_comparison.jl (default: test/legacy_comparison/output).
# It must contain the R exports, the Julia outputs written by compare.jl (DIR/julia/)
# and DIR/comparison_stats.csv, i.e. run_comparison.jl must have been run first
# (`--skip-r` is enough when the R exports already exist). run_comparison.jl calls
# this script itself at the end when CairoMakie can be loaded.
#
# Needs CairoMakie, which is not a dependency of the package. Install it once in your
# default environment: julia -e "using Pkg; Pkg.add(\"CairoMakie\")"
#
# Figures (PNG, written to DIR/figures/):
#   01_check_overview.png       every value check: largest relative difference vs its tolerance
#   02_centre_run.png           run at the prior means: legacy and Julia trajectories, relative difference
#   03_ensemble.png             CO2 / temperature quantile bands of all samples, and share of valid steps
#   04_one_to_one.png           Julia vs legacy for every finite cell (CO2, O2, temperature)
#   05_reldiff_histograms.png   distribution of relative differences before / at-after a failed step
#   06_reldiff_heatmaps.png     relative difference per run and age; failed steps in grey
#   07_reldiff_by_age.png       largest relative difference at each age, by region
#   08_percent_outbound.png     % outbound (acceptance criterion), Julia vs legacy
#   09_literals.png             effect of single- vs double-precision literals (finding F-05)
#
# "Relative difference" is |a − b| / max(|a|, |b|), as in compare.jl. Cells where both
# values are equal are drawn at 1e-18 and labelled "0".

using GeocarbPrecalibration
using CairoMakie
using Statistics

const GPP = GeocarbPrecalibration
const MK = CairoMakie.Makie

# colours (reference data-viz palette): Julia / "before any failure" blue,
# "at/after a failure" orange, legacy neutral grey, failures red, Float64 literals violet
const C_LEGACY = MK.RGBf(0x52 / 255, 0x51 / 255, 0x4e / 255)
const C_BLUE = MK.RGBf(0x2a / 255, 0x78 / 255, 0xd6 / 255)
const C_ORANGE = MK.RGBf(0xeb / 255, 0x68 / 255, 0x34 / 255)
const C_RED = MK.RGBf(0xe3 / 255, 0x49 / 255, 0x48 / 255)
const C_VIOLET = MK.RGBf(0x62 / 255, 0x50 / 255, 0xd6 / 255)
const C_GRID = MK.RGBf(0.85, 0.85, 0.84)

function _sup(k::Integer)
    d = Dict(
        '0' => '⁰',
        '1' => '¹',
        '2' => '²',
        '3' => '³',
        '4' => '⁴',
        '5' => '⁵',
        '6' => '⁶',
        '7' => '⁷',
        '8' => '⁸',
        '9' => '⁹',
    )
    return join(d[c] for c in string(k))
end

const ZERO_FLOOR = 1e-18          # where exactly equal cells are drawn on log axes
const LOG_EDGES = collect(-18.125:0.25:-0.875)  # bins centred on whole and quarter powers of ten
const LOG_TICKS = (collect(-18:2:-2), vcat(["0"], ["10⁻" * _sup(k) for k in 16:-2:2]))

# ---------------------------------------------------------------------------------------
# reading

function read_mat(path::AbstractString)
    t = read_csv_table(path)
    M = Matrix{Float64}(undef, length(t.rows), length(t.header))
    for (i, r) in enumerate(t.rows), j in eachindex(r)
        M[i, j] = GPP.parse_number(r[j]; allow_missing=true)
    end
    return t.header, M
end
mat(path) = read_mat(path)[2]

function read_stats(path::AbstractString)
    t = read_csv_table(path)
    col(nm) = findfirst(==(nm), t.header)
    num(r, nm) = GPP.parse_number(r[col(nm)]; allow_missing=true)
    return [
        (
            label=r[col("label")],
            n=round(Int, num(r, "n")),
            max_rel=num(r, "max_rel"),
            mismatches=round(Int, num(r, "inf_nan_mismatches")),
            bad=round(Int, num(r, "out_of_tolerance")),
            rtol=num(r, "rtol"),
            passed=lowercase(strip(r[col("passed")])) == "true",
        ) for r in t.rows
    ]
end

"Tolerances actually used (taken from the stats file, defaults of compare.jl otherwise)."
function tolerances(stats)
    clean = findfirst(s -> occursin("[before any failure]", s.label), stats)
    post = findfirst(s -> occursin("[at/after a failure]", s.label), stats)
    return (clean=clean === nothing ? 1e-8 : stats[clean].rtol, post=post === nothing ? 1e-4 : stats[post].rtol)
end

reldiff(x, y) = (isfinite(x) && isfinite(y)) ? (max(abs(x), abs(y)) > 0 ? abs(x - y) / max(abs(x), abs(y)) : 0.0) : NaN
floored(r) = isnan(r) ? NaN : max(r, ZERO_FLOOR)
logrel(r) = isnan(r) ? NaN : log10(floored(r))
post_failure(L::AbstractMatrix) = cumsum(isinf.(L); dims=2) .> 0
finite_or_nan(v) = [isfinite(x) ? x : NaN for x in v]

function load_comparison(dir::AbstractString)
    jdir = joinpath(dir, "julia")
    isdir(jdir) && isfile(joinpath(dir, "comparison_stats.csv")) ||
        error("$dir has no Julia outputs (julia/ and comparison_stats.csv); run run_comparison.jl first")
    W = mat(joinpath(dir, "legacy_windows.csv"))
    L = (
        co2=mat(joinpath(dir, "legacy_co2.csv")),
        o2=mat(joinpath(dir, "legacy_o2.csv")),
        temp=mat(joinpath(dir, "legacy_temp_plus15.csv")),
    )
    J = (
        co2=mat(joinpath(jdir, "julia_co2.csv")),
        o2=mat(joinpath(jdir, "julia_o2.csv")),
        temp=mat(joinpath(jdir, "julia_temp_plus15.csv")),
    )
    stats = read_stats(joinpath(dir, "comparison_stats.csv"))
    return (
        dir=dir,
        age=W[:, 1],
        windows=W,
        L=L,
        J=J,
        post=post_failure(L.co2),
        stats=stats,
        tol=tolerances(stats),
        jdir=jdir,
    )
end

const QUANTITIES = ((:co2, "CO₂", "CO₂ [ppmv]"), (:o2, "O₂", "O₂ [%]"), (:temp, "Temperature", "Temperature [°C]"))

# ---------------------------------------------------------------------------------------
# helpers

function log_counts(values::AbstractVector{<:Real})
    c = zeros(Int, length(LOG_EDGES) - 1)
    for v in values
        isnan(v) && continue
        k = searchsortedlast(LOG_EDGES, v)
        c[clamp(k, 1, length(c))] += 1
    end
    return (LOG_EDGES[1:(end - 1)] .+ LOG_EDGES[2:end]) ./ 2, c
end

const COUNT_TICKS = ([0, 1, 10, 100, 1_000, 10_000, 100_000], ["0", "1", "10", "100", "10³", "10⁴", "10⁵"])

function tolerance_lines!(ax, tol; horizontal=false, log=true)
    f = log ? log10 : identity
    if horizontal
        hlines!(ax, [f(tol.clean)]; color=C_BLUE, linestyle=:dash, linewidth=1.5)
        hlines!(ax, [f(tol.post)]; color=C_ORANGE, linestyle=:dash, linewidth=1.5)
    else
        vlines!(ax, [f(tol.clean)]; color=C_BLUE, linestyle=:dash, linewidth=1.5)
        vlines!(ax, [f(tol.post)]; color=C_ORANGE, linestyle=:dash, linewidth=1.5)
    end
    return ax
end

fmt(x) = x == 0 ? "0" : string(round(x; sigdigits=2))

# ---------------------------------------------------------------------------------------
# 1. overview of every check

function fig_check_overview(c)
    vals = filter(s -> !isnan(s.rtol), c.stats)
    masks = filter(s -> isnan(s.rtol), c.stats)
    n = length(vals)
    nmm = sum(s -> s.mismatches, c.stats; init=0)
    fig = Figure(; size=(1000, 150 + 15 * n))
    sub = string(
        count(s -> s.passed, c.stats),
        " of ",
        length(c.stats),
        " checks pass; ",
        if nmm == 0
            "Inf/NaN positions (pass/fail of every step) identical in all $(length(masks)) position checks"
        else
            "$nmm Inf/NaN position mismatches"
        end,
    )
    ax = Axis(
        fig[1, 1];
        xscale=log10,
        yreversed=true,
        title="Every value check: largest relative difference vs tolerance",
        subtitle=sub,
        xlabel="Largest relative difference (0 drawn at 10⁻¹⁸)",
        yticks=(1:n, [s.label for s in vals]),
        yticklabelsize=10,
        ygridvisible=false,
        xgridcolor=C_GRID,
    )
    xlims!(ax, ZERO_FLOOR / 3, 1.0)
    y = collect(1:n)
    tolx = [s.rtol > 0 ? s.rtol : NaN for s in vals]
    scatter!(ax, tolx, y; marker=:vline, markersize=14, color=C_LEGACY, label="tolerance (rtol)")
    ok = [s.passed for s in vals]
    xr = [floored(s.max_rel) for s in vals]
    scatter!(ax, xr[ok], y[ok]; color=C_BLUE, markersize=8, strokecolor=:white, strokewidth=1, label="pass")
    any(.!ok) && scatter!(ax, xr[.!ok], y[.!ok]; color=C_RED, marker=:xcross, markersize=12, label="FAIL")
    axislegend(ax; position=:rb, framevisible=false)
    return fig
end

# ---------------------------------------------------------------------------------------
# 2. centre run

function fig_centre_run(c)
    L = mat(joinpath(c.dir, "legacy_center_run.csv"))
    J = mat(joinpath(c.jdir, "julia_center_run.csv"))
    age = L[:, 1]
    x = -age
    ff = findfirst(isinf, L[:, 2])
    fig = Figure(; size=(1000, 750))
    Label(fig[0, 1:2], "Model at the prior means and time-array centres"; font=:bold, fontsize=16)
    for (k, (col, name, unit)) in
        enumerate(((2, "CO₂", "CO₂ [ppmv]"), (3, "O₂", "O₂ [%]"), (4, "Temperature", "ΔT [°C]")))
        a1 = Axis(
            fig[k, 1];
            ylabel=unit,
            yscale=col == 2 ? log10 : identity,
            xlabel=k == 3 ? "Time [Myr ago]" : "",
            title=k == 1 ? "Trajectory" : "",
        )
        a2 = Axis(
            fig[k, 2];
            ylabel="relative difference",
            yticks=LOG_TICKS,
            xlabel=k == 3 ? "Time [Myr ago]" : "",
            title=k == 1 ? "Julia vs legacy" : "",
        )
        if ff !== nothing
            vspan!(a1, [-age[ff] - 5], [5.0]; color=(C_ORANGE, 0.08))
            vspan!(a2, [-age[ff] - 5], [5.0]; color=(C_ORANGE, 0.08))
        end
        lines!(a1, x, finite_or_nan(L[:, col]); color=(C_LEGACY, 0.45), linewidth=6, label="legacy R/Fortran")
        lines!(a1, x, finite_or_nan(J[:, col]); color=C_BLUE, linewidth=2, label="Julia")
        r = [logrel(reldiff(J[i, col], L[i, col])) for i in eachindex(age)]
        tolerance_lines!(a2, c.tol; horizontal=true)
        scatter!(a2, x, r; color=C_BLUE, markersize=8)
        ylims!(a2, -18.5, -2)
        k == 1 && axislegend(a1; position=:rt, framevisible=false)
        linkxaxes!(a1, a2)
    end
    note = if ff === nothing
        "every step valid"
    else
        "first failed step at $(round(Int, age[ff])) Ma (shaded: at/after the failure)"
    end
    Label(
        fig[4, 1:2],
        "Dashed lines: tolerance before (blue) and at/after (orange) a failed step; $note";
        fontsize=11,
        color=C_LEGACY,
    )
    return fig
end

# ---------------------------------------------------------------------------------------
# 3. ensemble bands

function row_q(M, p)
    out = fill(NaN, size(M, 2))
    for j in axes(M, 2)
        v = filter(isfinite, view(M, :, j))
        isempty(v) || (out[j] = quantile(v, p))
    end
    return out
end

function fig_ensemble(c)
    x = -c.age
    n = size(c.L.co2, 1)
    fig = Figure(; size=(850, 900))
    Label(
        fig[0, 1],
        "All $n samples drawn by the R code: legacy (grey bands) and Julia (blue lines)";
        font=:bold,
        fontsize=15,
    )
    for (k, (s, unit, logy)) in enumerate(((:co2, "CO₂ [ppmv]", true), (:temp, "Temperature [°C]", false)))
        ax = Axis(fig[k, 1]; ylabel=unit, yscale=logy ? log10 : identity)
        Lm = getfield(c.L, s)
        Jm = getfield(c.J, s)
        logy && (Lm = map(v -> v > 0 ? v : NaN, Lm); Jm = map(v -> v > 0 ? v : NaN, Jm))
        band!(ax, x, row_q(Lm, 0.025), row_q(Lm, 0.975); color=(C_LEGACY, 0.18), label="legacy 95 %")
        band!(ax, x, row_q(Lm, 0.25), row_q(Lm, 0.75); color=(C_LEGACY, 0.35), label="legacy 50 %")
        lines!(ax, x, row_q(Lm, 0.5); color=(C_LEGACY, 0.6), linewidth=5, label="legacy median")
        for p in (0.025, 0.25, 0.75, 0.975)
            lines!(
                ax,
                x,
                row_q(Jm, p);
                color=C_BLUE,
                linewidth=1,
                linestyle=:dash,
                label=p == 0.025 ? "Julia quantiles" : nothing,
            )
        end
        lines!(ax, x, row_q(Jm, 0.5); color=C_BLUE, linewidth=2, label="Julia median")
        k == 1 && axislegend(ax; position=:rt, framevisible=false, labelsize=11)
    end
    ax = Axis(
        fig[3, 1];
        ylabel="valid runs [%]",
        xlabel="Time [Myr ago]",
        title="Share of runs whose CO₂ step is valid (not Inf/NaN)",
    )
    vl = [100 * count(isfinite, view(c.L.co2, :, j)) / n for j in axes(c.L.co2, 2)]
    vj = [100 * count(isfinite, view(c.J.co2, :, j)) / n for j in axes(c.J.co2, 2)]
    lines!(ax, x, vl; color=(C_LEGACY, 0.45), linewidth=6, label="legacy")
    lines!(ax, x, vj; color=C_BLUE, linewidth=2, label="Julia")
    axislegend(ax; position=:rb, framevisible=false)
    rowsize!(fig.layout, 3, Relative(0.22))
    return fig
end

# ---------------------------------------------------------------------------------------
# 4. one-to-one

function fig_one_to_one(c)
    fig = Figure(; size=(1200, 430))
    Label(fig[0, 1:3], "Julia vs legacy, every finite cell (runs × time steps)"; font=:bold, fontsize=15)
    for (k, (s, name, unit)) in enumerate(QUANTITIES)
        Lm = getfield(c.L, s)
        Jm = getfield(c.J, s)
        ok = isfinite.(Lm) .& isfinite.(Jm)
        s == :co2 && (ok .&= (Lm .> 0) .& (Jm .> 0))
        sc = s == :co2 ? log10 : identity
        ax = Axis(
            fig[1, k];
            title=name,
            xlabel="legacy  " * unit,
            ylabel=k == 1 ? "Julia" : "",
            xscale=sc,
            yscale=sc,
            aspect=1,
        )
        a = ok .& c.post
        b = ok .& .!c.post
        scatter!(ax, Lm[a], Jm[a]; color=(C_ORANGE, 0.5), markersize=4, label="at/after a failure ($(count(a)))")
        scatter!(ax, Lm[b], Jm[b]; color=(C_BLUE, 0.5), markersize=4, label="before any failure ($(count(b)))")
        lo, hi = extrema(vcat(Lm[ok], Jm[ok]))
        lines!(ax, [lo, hi], [lo, hi]; color=C_LEGACY, linewidth=1)
        mr = maximum((reldiff(Jm[I], Lm[I]) for I in findall(ok)); init=0.0)
        text!(ax, 0.03, 0.97; text="max rel. diff. " * fmt(mr), space=:relative, align=(:left, :top), fontsize=11)
        k == 3 && axislegend(ax; position=:rb, framevisible=false, labelsize=10)
    end
    return fig
end

# ---------------------------------------------------------------------------------------
# 5. histograms

function fig_histograms(c)
    fig = Figure(; size=(1100, 820))
    Label(fig[0, 1], "Distribution of relative differences, Julia vs legacy"; font=:bold, fontsize=15)
    for (k, (s, name, _)) in enumerate(QUANTITIES)
        Lm = getfield(c.L, s)
        Jm = getfield(c.J, s)
        R = reldiff.(Jm, Lm)
        ax = Axis(
            fig[k, 1];
            title=name,
            xticks=LOG_TICKS,
            ylabel="cells",
            yscale=MK.pseudolog10,
            yticks=COUNT_TICKS,
            xlabel=k == 3 ? "relative difference" : "",
        )
        for (mask, col, lab) in ((.!c.post, C_BLUE, "before any failure"), (c.post, C_ORANGE, "at/after a failure"))
            v = logrel.(R[mask])
            ctr, cnt = log_counts(v)
            nz = count(==(0.0), R[mask])
            barplot!(
                ax,
                ctr,
                cnt;
                width=0.25,
                gap=0,
                color=(col, 0.55),
                label="$lab: $(count(!isnan, v)) cells, $nz identical",
            )
        end
        tolerance_lines!(ax, c.tol)
        xlims!(ax, -18.5, -1.5)
        axislegend(ax; position=:rt, framevisible=false, labelsize=11)
    end
    Label(
        fig[4, 1],
        "Dashed: tolerance before (blue, $(fmt(c.tol.clean))) and at/after (orange, $(fmt(c.tol.post))) a run's first failed step. " *
        "Leftmost bar: exactly equal.";
        fontsize=11,
        color=C_LEGACY,
    )
    return fig
end

# ---------------------------------------------------------------------------------------
# 6. heatmaps

function fig_heatmaps(c)
    n, nt = size(c.L.co2)
    ff = [something(findfirst(view(c.post, i, :)), nt + 1) for i in 1:n]
    order = sortperm(ff; rev=true)              # runs that never fail at the top
    x = -c.age
    fig = Figure(; size=(1300, 700))
    Label(
        fig[0, 1:4],
        "Relative difference per run and time step (runs sorted by the age of their first failure; grey = failed step)";
        font=:bold,
        fontsize=15,
    )
    hm = nothing
    for (k, (s, name, _)) in enumerate(QUANTITIES)
        Lm = getfield(c.L, s)[order, :]
        Jm = getfield(c.J, s)[order, :]
        Z = permutedims(logrel.(reldiff.(Jm, Lm)))      # time × runs
        ax = Axis(fig[1, k]; title=name, xlabel="Time [Myr ago]", ylabel=k == 1 ? "run (sorted)" : "", yreversed=true)
        hm = heatmap!(ax, x, 1:n, Z; colormap=:Blues, colorrange=(-18, -2), nan_color=(C_LEGACY, 0.55))
        stairs_x = [ff[i] <= nt ? x[ff[i]] : NaN for i in order]
        lines!(ax, stairs_x, 1:n; color=C_ORANGE, linewidth=1.5, label="first failed step")
        k == 1 && axislegend(ax; position=:lb, framevisible=true, labelsize=10)
    end
    Colorbar(fig[1, 4], hm; label="relative difference", ticks=LOG_TICKS)
    return fig
end

# ---------------------------------------------------------------------------------------
# 7. by age

function fig_by_age(c)
    x = -c.age
    fig = Figure(; size=(900, 800))
    Label(fig[0, 1], "Largest relative difference over all runs, per time step"; font=:bold, fontsize=15)
    for (k, (s, name, _)) in enumerate(QUANTITIES)
        Lm = getfield(c.L, s)
        Jm = getfield(c.J, s)
        R = reldiff.(Jm, Lm)
        ax = Axis(
            fig[k, 1]; title=name, yticks=LOG_TICKS, ylabel="relative difference", xlabel=k == 3 ? "Time [Myr ago]" : ""
        )
        tolerance_lines!(ax, c.tol; horizontal=true)
        for (mask, col, lab) in ((.!c.post, C_BLUE, "before any failure"), (c.post, C_ORANGE, "at/after a failure"))
            mx = fill(NaN, length(x))
            md = fill(NaN, length(x))
            for j in eachindex(x)
                v = filter(!isnan, R[view(mask, :, j), j])
                isempty(v) && continue
                mx[j] = log10(floored(maximum(v)))
                md[j] = log10(floored(median(v)))
            end
            lines!(ax, x, md; color=(col, 0.6), linewidth=1.5, linestyle=:dot, label="$lab, median")
            scatterlines!(ax, x, mx; color=col, markersize=6, linewidth=1.5, label="$lab, max")
        end
        ylims!(ax, -18.5, -2)
        k == 1 && axislegend(ax; position=:lt, framevisible=false, labelsize=10, nbanks=2)
    end
    return fig
end

# ---------------------------------------------------------------------------------------
# 8. % outbound

function fig_percent_outbound(c)
    P = mat(joinpath(c.dir, "legacy_prcout.csv"))
    Q = mat(joinpath(c.jdir, "julia_prcout.csv"))
    fig = Figure(; size=(900, 470))
    Label(
        fig[0, 1:2],
        "% outbound (fraction of time steps outside the windows) — decides acceptance";
        font=:bold,
        fontsize=15,
    )
    for (k, name) in enumerate(("CO₂", "Temperature"))
        same = count(i -> P[i, k] == Q[i, k], axes(P, 1))
        ax = Axis(
            fig[1, k];
            title="$name: identical in $same of $(size(P, 1)) runs",
            xlabel="legacy",
            ylabel=k == 1 ? "Julia" : "",
            aspect=1,
        )
        lines!(ax, [0, 1], [0, 1]; color=C_LEGACY, linewidth=1)
        d = [P[i, k] == Q[i, k] for i in axes(P, 1)]
        scatter!(ax, P[d, k], Q[d, k]; color=(C_BLUE, 0.35), markersize=7, label="identical")
        any(.!d) && scatter!(ax, P[.!d, k], Q[.!d, k]; color=C_RED, marker=:xcross, markersize=12, label="different")
        k == 2 && axislegend(ax; position=:rb, framevisible=false)
    end
    return fig
end

# ---------------------------------------------------------------------------------------
# 9. literals

function fig_literals(c)
    f64 = joinpath(c.jdir, "julia_co2_float64_literals.csv")
    isfile(f64) || return nothing
    J64 = mat(f64)
    L = c.L.co2
    flips = count(isinf.(J64) .!= isinf.(L))
    fig = Figure(; size=(1000, 480))
    ax = Axis(
        fig[1, 1];
        title="CO₂ before any failure: why the port keeps the Fortran single-precision literals (finding F-05)",
        subtitle="Float64 literals: $flips pass/fail flips against the legacy output (single-precision literals: " *
                 "$(count(isinf.(c.J.co2) .!= isinf.(L))))",
        xticks=LOG_TICKS,
        xlabel="relative difference to the legacy CO₂",
        ylabel="cells",
        yscale=MK.pseudolog10,
        yticks=COUNT_TICKS,
    )
    for (M, col, lab) in (
        (c.J.co2, C_BLUE, "fortran_single_literals = true (default)"),
        (J64, C_VIOLET, "fortran_single_literals = false"),
    )
        v = [logrel(reldiff(M[I], L[I])) for I in CartesianIndices(L) if !c.post[I]]
        ctr, cnt = log_counts(v)
        barplot!(ax, ctr, cnt; width=0.25, gap=0, color=(col, 0.55), label=lab)
    end
    vlines!(ax, [log10(c.tol.clean)]; color=C_BLUE, linestyle=:dash, linewidth=1.5)
    xlims!(ax, -18.5, -1.5)
    axislegend(ax; position=:rt, framevisible=false)
    return fig
end

# ---------------------------------------------------------------------------------------

"""
    plot_legacy_comparison(dir; figdir = joinpath(dir, "figures"), px_per_unit = 2) -> Vector{String}

Draw the comparison figures from the files written by `run_comparison.jl` and return
the paths of the PNGs.
"""
function plot_legacy_comparison(
    dir::AbstractString; figdir::AbstractString=joinpath(dir, "figures"), px_per_unit::Real=2
)
    c = load_comparison(dir)
    mkpath(figdir)
    figs = (
        ("01_check_overview.png", fig_check_overview),
        ("02_centre_run.png", fig_centre_run),
        ("03_ensemble.png", fig_ensemble),
        ("04_one_to_one.png", fig_one_to_one),
        ("05_reldiff_histograms.png", fig_histograms),
        ("06_reldiff_heatmaps.png", fig_heatmaps),
        ("07_reldiff_by_age.png", fig_by_age),
        ("08_percent_outbound.png", fig_percent_outbound),
        ("09_literals.png", fig_literals),
    )
    written = String[]
    for (name, f) in figs
        try
            fig = f(c)
            fig === nothing && continue
            path = joinpath(figdir, name)
            CairoMakie.save(path, fig; px_per_unit=px_per_unit)
            push!(written, path)
            println("  figure: ", path)
        catch err
            @warn "figure $name failed" exception = (err, catch_backtrace())
        end
    end
    return written
end

if abspath(PROGRAM_FILE) == @__FILE__
    plot_legacy_comparison(isempty(ARGS) ? joinpath(@__DIR__, "output") : ARGS[1])
end
