# Compare the Julia port with the exports of run_legacy.R (the original R/Fortran code).
#
# Checked, in order:
#   1. input pipeline: time-array centres and σ, inverse-Wishart degrees of freedom,
#      CO2 and temperature windows;
#   2. prior transform: R's rescaled LHS probabilities → parameter values;
#   3. the model on every sample R kept (constants + sampled forcings): CO2, O2 and
#      temperature at all 58 steps;
#   4. % outbound of CO2 and temperature;
#   5. the model at the prior means / time-array centres;
#   6. the six supplemental-experiment variants of run_geocarb_supp.f90;
#   7. if the compiled Fortran can be loaded directly, a ccall check that R passed the
#      inputs through unchanged.
#
# How model outputs are judged (see docs/src/testing.md and the debug report of the
# first test run):
#
#   * Inf/NaN positions, i.e. every pass/fail decision, must be identical.
#   * % outbound must be identical (it decides acceptance).
#   * Values in the "clean" part of a run (no failed step so far, inclusive) must agree
#     within rtol_clean (default 1e-8). This is the machine-noise criterion: injecting
#     1-ulp errors into exp/log/pow moves these values by at most ~4e-9.
#   * Values at or after a run's first failed step must agree within rtol_post
#     (default 1e-4). The legacy model keeps integrating from an invalid state after a
#     failure (finding F-08), and there 1-ulp differences between maths libraries grow
#     to ~1e-6. Even two builds of the same Fortran differ there.
#
# The comparison uses ModelOptions(fortran_single_literals = true), i.e. the literals
# of the compiled code (finding F-05). Float64 literals are reported for information.

using Test
using GeocarbPrecalibration
using GeocarbPrecalibration: @sprintf, parse_number, quantile_from_cdf, _legacy_percent_outbound_shifted
const GP = GeocarbPrecalibration
include(joinpath(@__DIR__, "fortran_ffi.jl"))

# Default tolerances: test/tolerances.toml is the single source (the golden-master test
# reads it too). The TOML stdlib is reached through the package, which loads it.
const TOLERANCES = GP.TOML.parsefile(joinpath(@__DIR__, "..", "tolerances.toml"))
const RTOL_CLEAN = Float64(TOLERANCES["rtol_clean"])
const RTOL_POST = Float64(TOLERANCES["rtol_post"])
const ATOL = Float64(TOLERANCES["atol"])

struct DiffStats
    label::String
    n::Int
    max_abs::Float64
    max_rel::Float64
    mask_mismatch::Int
    n_bad::Int
    rtol::Float64          # relative tolerance applied (NaN for a pass/fail-position check)
end
passed(s::DiffStats) = s.mask_mismatch == 0 && s.n_bad == 0

function diffstats(label::AbstractString, a::AbstractArray, b::AbstractArray; rtol::Real, atol::Real)
    size(a) == size(b) || error("$label: size mismatch $(size(a)) vs $(size(b))")
    maxa = 0.0
    maxr = 0.0
    mm = 0
    bad = 0
    for (x, y) in zip(a, b)
        if isnan(x) || isnan(y)
            (isnan(x) && isnan(y)) || (mm += 1)
        elseif isinf(x) || isinf(y)
            x == y || (mm += 1)
        else
            d = abs(x - y)
            s = max(abs(x), abs(y))
            maxa = max(maxa, d)
            s > 0 && (maxr = max(maxr, d / s))
            d <= atol + rtol * s || (bad += 1)
        end
    end
    return DiffStats(String(label), length(a), maxa, maxr, mm, bad, Float64(rtol))
end

"Only the Inf/NaN positions (pass/fail decisions); finite values are not compared."
function maskstats(label::AbstractString, a::AbstractArray, b::AbstractArray)
    size(a) == size(b) || error("$label: size mismatch $(size(a)) vs $(size(b))")
    mm = count(
        ((x, y),) -> (isnan(x) != isnan(y)) || (isinf(x) != isinf(y)) || (isinf(x) && isinf(y) && x != y), zip(a, b)
    )
    return DiffStats(String(label), length(a), 0.0, 0.0, mm, 0, NaN)
end

function relative_difference(x, y)
    return (isfinite(x) && isfinite(y) && max(abs(x), abs(y)) > 0) ? abs(x - y) / max(abs(x), abs(y)) : 0.0
end

"""
    post_failure(legacy_co2) -> BitMatrix

`true` for the cells (runs × steps) at or after the first failed step (CO2 = Inf) of
each run.
"""
post_failure(legacy_co2::AbstractMatrix) = cumsum(isinf.(legacy_co2); dims=2) .> 0

function read_matrix(path::AbstractString)
    t = read_csv_table(path)
    M = Matrix{Float64}(undef, length(t.rows), length(t.header))
    for (i, r) in enumerate(t.rows), j in eachindex(r)
        M[i, j] = parse_number(r[j]; allow_missing=true)     # R's NA becomes NaN
    end
    return t.header, M
end

function legacy_samples(dir::AbstractString, age::Vector{Float64})
    hc, C = read_matrix(joinpath(dir, "constants.csv"))
    ht, TS = read_matrix(joinpath(dir, "time_series.csv"))
    cols = Dict{Symbol,Vector{Int}}()
    for (j, h) in enumerate(ht)
        nm, st = rsplit(h, "_"; limit=2)
        v = get!(cols, Symbol(nm), Int[])
        push!(v, j)
        parse(Int, st) == length(v) || error("unexpected column order in time_series.csv at $h")
    end
    names_c = Symbol.(hc)
    samples = Tuple{ConstantParams{Float64},TimeForcings{Float64}}[]
    for i in axes(C, 1)
        d = Dict{Symbol,Vector{Float64}}(nm => TS[i, js] for (nm, js) in cols)
        push!(samples, (ConstantParams(names_c, C[i, :]), TimeForcings(age, d; check_finite=false)))
    end
    return samples
end

"Julia outputs as runs × steps matrices, with the step status and solver iterations."
function julia_outputs(samples, options::ModelOptions)
    n = length(samples)
    nt = length(first(samples)[2].age)
    co2 = Matrix{Float64}(undef, n, nt)
    o2 = similar(co2)
    temp = similar(co2)
    status = Matrix{StepStatus}(undef, n, nt)
    iters = Matrix{Int}(undef, n, nt)
    for (i, (p, f)) in enumerate(samples)
        r = run_geocarb(p, f; options=options)
        co2[i, :] .= r.co2
        o2[i, :] .= r.o2
        temp[i, :] .= r.temp
        status[i, :] .= r.status
        iters[i, :] .= r.iterations
    end
    return (co2=co2, o2=o2, temp=temp, status=status, iterations=iters)
end

"""
    write_matrix(path, M)

Write a runs × steps matrix with the header of the legacy exports (`step_1`, …), so the
Julia outputs can be read back exactly like the R ones (used by `plot_comparison.jl`).
"""
function write_matrix(path::AbstractString, M::AbstractMatrix)
    return GP.write_csv(path, ["step_$j" for j in axes(M, 2)], [M[:, j] for j in axes(M, 2)])
end

function write_stats_csv(path::AbstractString, stats::AbstractVector{DiffStats})
    return GP.write_csv(
        path,
        ["label", "n", "max_abs", "max_rel", "inf_nan_mismatches", "out_of_tolerance", "rtol", "passed"],
        [
            [s.label for s in stats],
            [s.n for s in stats],
            [s.max_abs for s in stats],
            [s.max_rel for s in stats],
            [s.mask_mismatch for s in stats],
            [s.n_bad for s in stats],
            [s.rtol for s in stats],
            [passed(s) for s in stats],
        ],
    )
end

function format_stats(s::DiffStats)
    return @sprintf(
        "  %-52s n=%8d  max|Δ|=%.3e  max rel=%.3e  Inf/NaN mismatches=%d  out of tolerance=%d  %s",
        s.label,
        s.n,
        s.max_abs,
        s.max_rel,
        s.mask_mismatch,
        s.n_bad,
        passed(s) ? "OK" : "FAIL"
    )
end

"""
    compare_with_legacy(dir; rtol_clean = RTOL_CLEAN, rtol_post = RTOL_POST, atol = ATOL,
                        fortran_dir = nothing, worst = 10) -> Vector{DiffStats}

Run all comparisons on the exports in `dir` and record them as `@test`s. The default
tolerances come from `test/tolerances.toml`. Writes
`dir/comparison_report.txt`, including the `worst` largest differences in each region
with the Julia step status, so any real discrepancy can be located. The Julia outputs
are written to `dir/julia/` and the statistics of every check to
`dir/comparison_stats.csv`; `plot_comparison.jl` draws its figures from these files.
"""
function compare_with_legacy(
    dir::AbstractString;
    rtol_clean::Real=RTOL_CLEAN,
    rtol_post::Real=RTOL_POST,
    atol::Real=ATOL,
    fortran_dir::Union{Nothing,AbstractString}=nothing,
    worst::Integer=10,
)
    report = String[]
    say(s) = (println(s); push!(report, s))
    all_stats = DiffStats[]
    check!(s) = (push!(all_stats, s); say(format_stats(s)); @test passed(s); s)
    say(
        @sprintf(
            "tolerances: rtol_clean = %.1e (before any failed step), rtol_post = %.1e (at/after a failed step), atol = %.1e",
            rtol_clean,
            rtol_post,
            atol
        ),
    )
    isfile(joinpath(dir, "legacy_meta.txt")) &&
        foreach(l -> say("  legacy | " * l), readlines(joinpath(dir, "legacy_meta.txt")))

    # Pass/fail mask, clean region and post-failure region of one output quantity.
    # J and L are runs × steps; `post` marks the post-failure cells; `jo` holds the
    # Julia statuses and iteration counts for the worst-cell listing.
    function region_checks!(label, J, L, post, ages, jo; nworst=worst)
        check!(maskstats("$label: pass/fail (Inf/NaN) positions", J, L))
        check!(diffstats("$label [before any failure]", J[.!post], L[.!post]; rtol=rtol_clean, atol=atol))
        check!(diffstats("$label [at/after a failure]", J[post], L[post]; rtol=rtol_post, atol=atol))
        nworst > 0 || return nothing
        for (region, mask) in (("before any failure", .!post), ("at/after a failure", post))
            cells = [(relative_difference(J[I], L[I]), I) for I in CartesianIndices(J) if mask[I]]
            filter!(c -> c[1] > 0, cells)
            isempty(cells) && continue
            sort!(cells; by=first, rev=true)
            say("    worst $label cells $region:")
            for (rel, I) in cells[1:min(nworst, length(cells))]
                i, j = Tuple(I)
                ff = findfirst(post[i, :])
                say(
                    @sprintf(
                        "      run %4d  age %3d Ma  status %-21s iter %2d  first failure %-7s legacy % .12e  julia % .12e  rel %.2e",
                        i,
                        round(Int, ages[j]),
                        string(jo.status[i, j]),
                        jo.iterations[i, j],
                        ff === nothing ? "none" : "$(round(Int, ages[ff])) Ma",
                        L[I],
                        J[I],
                        rel
                    ),
                )
            end
        end
        return nothing
    end

    # 1. inputs ---------------------------------------------------------------------
    say("1. input pipeline")
    tp = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
    hc, C = read_matrix(joinpath(dir, "legacy_time_center.csv"))
    _, S = read_matrix(joinpath(dir, "legacy_time_sigma.csv"))
    jc = reduce(hcat, [getfield(tp.center, Symbol(h)) for h in hc])
    js = reduce(hcat, [getfield(tp.sigma, Symbol(h)) for h in hc])
    check!(diffstats("time-array centres (Goddéris, fAw/fA normalised)", jc, C; rtol=rtol_clean, atol=atol))
    check!(diffstats("time-array standard deviations", js, S; rtol=rtol_clean, atol=atol))
    hd, D = read_matrix(joinpath(dir, "legacy_dof.csv"))
    dof = inverse_wishart_dof(tp.sigma, read_variance_reduction())
    check!(
        diffstats("inverse-Wishart degrees of freedom", [Float64(dof[Symbol(h)]) for h in hd], vec(D); rtol=0, atol=0)
    )
    _, W = read_matrix(joinpath(dir, "legacy_windows.csv"))
    age = W[:, 1]
    @test age == tp.center.age
    cw = co2_windows(read_proxy_data(datapath("CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv")), age)
    tw = temperature_windows(read_temperature_data(datapath("Mills_GR_2019_temp_co2.csv")), age)
    check!(diffstats("CO2 windows", hcat(cw.low, cw.high), W[:, 2:3]; rtol=rtol_clean, atol=atol))
    check!(diffstats("temperature windows", hcat(tw.low, tw.high), W[:, 4:5]; rtol=rtol_clean, atol=atol))

    # 2. prior transform --------------------------------------------------------------
    say("2. prior transform (Latin hypercube probabilities → parameter values)")
    hl, L = read_matrix(joinpath(dir, "legacy_lhs_cdf.csv"))
    _, V = read_matrix(joinpath(dir, "legacy_lhs_values.csv"))
    priors = Dict(
        p.name => p for p in build_priors(read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv")))
    )
    J = [quantile_from_cdf(priors[Symbol(hl[j])], L[i, j]) for i in axes(L, 1), j in axes(L, 2)]
    check!(diffstats("truncated-prior quantiles", J, V; rtol=rtol_clean, atol=atol))

    # 3. model on the legacy samples ----------------------------------------------------
    samples = legacy_samples(dir, age)
    say("3. model outputs for $(length(samples)) samples drawn by the R code (fortran_single_literals = true)")
    _, Rco2 = read_matrix(joinpath(dir, "legacy_co2.csv"))
    _, Ro2 = read_matrix(joinpath(dir, "legacy_o2.csv"))
    _, Rtemp = read_matrix(joinpath(dir, "legacy_temp_plus15.csv"))
    post = post_failure(Rco2)
    say(
        @sprintf(
            "  legacy outputs: %d of %d steps failed (Inf); %d of %d cells lie before any failed step; %d samples with every step valid",
            count(isinf, Rco2),
            length(Rco2),
            count(.!post),
            length(post),
            count(i -> all(isfinite, view(Rco2, i, :)), axes(Rco2, 1))
        ),
    )
    opt = ModelOptions(; fortran_single_literals=true)
    o = julia_outputs(samples, opt)
    jdir = mkpath(joinpath(dir, "julia"))
    write_matrix(joinpath(jdir, "julia_co2.csv"), o.co2)
    write_matrix(joinpath(jdir, "julia_o2.csv"), o.o2)
    write_matrix(joinpath(jdir, "julia_temp_plus15.csv"), o.temp .+ 15)
    write_matrix(joinpath(jdir, "julia_status.csv"), Int.(o.status))
    region_checks!("CO2", o.co2, Rco2, post, age, o)
    region_checks!("O2", o.o2, Ro2, post, age, o)
    region_checks!("temperature + 15", o.temp .+ 15, Rtemp, post, age, o)

    # Float64 literals: information only (finding F-05)
    o64 = julia_outputs(samples, ModelOptions(; fortran_single_literals=false))
    write_matrix(joinpath(jdir, "julia_co2_float64_literals.csv"), o64.co2)
    flips = count(isinf.(o64.co2) .!= isinf.(Rco2))
    clean_rel = [relative_difference(o64.co2[I], Rco2[I]) for I in CartesianIndices(Rco2) if !post[I]]
    say(
        @sprintf(
            "  [information] Float64 literals instead: %d pass/fail flips; CO2 before any failure: median rel %.1e, max rel %.1e",
            flips,
            isempty(clean_rel) ? 0.0 : GP.median(clean_rel),
            isempty(clean_rel) ? 0.0 : maximum(clean_rel)
        ),
    )

    # 4. % outbound ----------------------------------------------------------------------
    say("4. percent outbound")
    _, P = read_matrix(joinpath(dir, "legacy_prcout.csv"))
    pc = [legacy_percent_outbound(o.co2[i, :], cw) for i in axes(o.co2, 1)]
    pt = [_legacy_percent_outbound_shifted(o.temp[i, :], 15.0, tw) for i in axes(o.temp, 1)]
    GP.write_csv(joinpath(jdir, "julia_prcout.csv"), ["co2", "temp"], [pc, pt])
    check!(diffstats("% outbound CO2", pc, P[:, 1]; rtol=0, atol=1e-12))
    check!(diffstats("% outbound temperature", pt, P[:, 2]; rtol=0, atol=1e-12))

    # 5. centre run ------------------------------------------------------------------------
    say("5. model at prior means and time-array centres")
    _, CR = read_matrix(joinpath(dir, "legacy_center_run.csv"))
    rc = run_geocarb(
        mean_constants(read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))), tp.center; options=opt
    )
    GP.write_csv(joinpath(jdir, "julia_center_run.csv"), ["age", "co2", "o2", "temp"], [age, rc.co2, rc.o2, rc.temp])
    rco = (status=permutedims(rc.status), iterations=permutedims(rc.iterations))
    cpost = post_failure(permutedims(CR[:, 2]))
    region_checks!("centre run CO2", permutedims(rc.co2), permutedims(CR[:, 2]), cpost, age, rco; nworst=0)
    region_checks!("centre run O2", permutedims(rc.o2), permutedims(CR[:, 3]), cpost, age, rco; nworst=0)
    region_checks!(
        "centre run temperature + 15",
        permutedims(rc.temp .+ 15),
        permutedims(CR[:, 4] .+ 15),
        cpost,
        age,
        rco;
        nworst=0,
    )

    # 6. supplemental variants -------------------------------------------------------------
    names_supp = readlines(joinpath(dir, "legacy_supp_names.txt"))
    _, SC = read_matrix(joinpath(dir, "legacy_supp_configs.csv"))
    say("6. supplemental-experiment variants (run_geocarb_supp.f90)")
    for (k, nm) in enumerate(names_supp)
        beg, en, gym, dT2X = SC[k, :]
        sopt = ModelOptions(;
            gym_angio_transition=(beg, en), gym_factor=gym, dT2X_ramp=dT2X >= 0, fortran_single_literals=true
        )
        _, Sco2 = read_matrix(joinpath(dir, "legacy_supp_$(nm)_co2.csv"))
        _, So2 = read_matrix(joinpath(dir, "legacy_supp_$(nm)_o2.csv"))
        _, Stemp = read_matrix(joinpath(dir, "legacy_supp_$(nm)_temp.csv"))
        so = julia_outputs(samples[1:size(Sco2, 1)], sopt)
        write_matrix(joinpath(jdir, "julia_supp_$(nm)_co2.csv"), so.co2)
        write_matrix(joinpath(jdir, "julia_supp_$(nm)_o2.csv"), so.o2)
        write_matrix(joinpath(jdir, "julia_supp_$(nm)_temp.csv"), so.temp)
        spost = post_failure(Sco2)
        region_checks!("supp $nm CO2", so.co2, Sco2, spost, age, so; nworst=3)
        region_checks!("supp $nm O2", so.o2, So2, spost, age, so; nworst=3)
        region_checks!("supp $nm temperature + 15", so.temp .+ 15, Stemp .+ 15, spost, age, so; nworst=3)
    end

    # 7. optional direct Fortran call --------------------------------------------------------
    if fortran_dir !== nothing
        lib = find_fortran_lib(fortran_dir, "run_geocarb")
        fptr = lib === nothing ? nothing : fortran_symbol(lib, :run_geocarb_)
        if fptr === nothing
            say("7. direct ccall of the Fortran library: skipped (library not found or not loadable)")
        else
            say("7. direct ccall of $lib (same inputs, no R)")
            F = [fortran_run(fptr, p, f) for (p, f) in samples]
            Fco2 = reduce(vcat, [permutedims(x[1]) for x in F])
            Ftemp = reduce(vcat, [permutedims(x[3]) for x in F])
            check!(diffstats("ccall Fortran vs R .Fortran (CO2, bit for bit)", Fco2, Rco2; rtol=0, atol=0))
            region_checks!(
                "ccall Fortran vs Julia temperature + 15",
                o.temp .+ 15,
                Ftemp .+ 15,
                post_failure(Fco2),
                age,
                o;
                nworst=0,
            )
        end
    end

    nok = count(passed, all_stats)
    clean_stats = filter(s -> occursin("[before any failure]", s.label), all_stats)
    post_stats = filter(s -> occursin("[at/after a failure]", s.label), all_stats)
    say(
        @sprintf(
            "SUMMARY: %d of %d comparisons pass. Largest relative difference before any failure %.3e (tolerance %.1e); at/after a failure %.3e (tolerance %.1e)",
            nok,
            length(all_stats),
            isempty(clean_stats) ? 0.0 : maximum(s -> s.max_rel, clean_stats),
            rtol_clean,
            isempty(post_stats) ? 0.0 : maximum(s -> s.max_rel, post_stats),
            rtol_post
        ),
    )
    write(joinpath(dir, "comparison_report.txt"), join(report, "\n") * "\n")
    write_stats_csv(joinpath(dir, "comparison_stats.csv"), all_stats)
    return all_stats
end
