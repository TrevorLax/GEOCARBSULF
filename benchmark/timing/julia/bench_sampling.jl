# bench_sampling.jl: Julia side of the sampling components (plan §3.3)
#   P1  random_lhs(rng, n, 56)
#   P2  transform_unit (truncated-prior quantiles)
#   P3  time-series sampling per sample: inverse Wishart (with and without returning the
#       covariances), multivariate t, and the normalisation alone
#   P4  covariance storage (appending the 12 covariance draws of each sample, as the engine does)
#   P5  raw RNG throughput (StableRNG and the default Xoshiro)

include(joinpath(@__DIR__, "..", "lib", "common.jl"))
job = read_job(ARGS[1])
w = RawWriter(job)
using GeocarbPrecalibration
using GeocarbPrecalibration: StableRNG, transform_unit, quantile_from_cdf
const GP = GeocarbPrecalibration
using Distributions: Chisq
include_legacy_helpers()

exports = jstr(job, "exports_dir")
table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
const priors = build_priors(table)
const np = length(priors)
tp = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
fvr = read_variance_reduction()
const iw = InverseWishartSampler(tp.center, tp.sigma, fvr)
const mt = MultivariateTSampler(tp.center, tp.sigma, fvr)
const nt = length(tp.center.age)

# --- P1 + P2 -------------------------------------------------------------------------
random_lhs(StableRNG(1), 100, np);
transform_unit(random_lhs(StableRNG(1), 100, np), priors);
for n in jints(job, "lhs_sizes")
    component!(w, "J", "P1"; workload="n=$n") do
        m = measure(() -> random_lhs(StableRNG(jint(job, "rep", 1)), n, np))
        U = m.value
        check(size(U) == (n, np) && all(x -> 0 < x < 1, U), "random_lhs: bad design")
        record!(w, m; variant="J", component="P1", subcomponent="random_lhs", workload="n=$n", n=n)
        m2 = measure(() -> transform_unit(U, priors))
        X = m2.value
        check(
            all(isfinite, X) &&
                all(all(p.lower <= x <= p.upper for x in view(X, :, j)) for (j, p) in enumerate(priors)),
            "transform_unit: value outside its truncation bounds",
        )
        return record!(w, m2; variant="J", component="P2", subcomponent="transform_unit", workload="n=$n", n=n)
    end
end
component!(w, "J", "P2-guard") do      # same check as the legacy comparison (max 1.1e-12 there)
    hl, L = read_matrix(joinpath(exports, "legacy_lhs_cdf.csv"))
    _, V = read_matrix(joinpath(exports, "legacy_lhs_values.csv"))
    pr = Dict(p.name => p for p in priors)
    J = [quantile_from_cdf(pr[Symbol(hl[j])], L[i, j]) for i in axes(L, 1), j in axes(L, 2)]
    return check(maximum(abs.(J .- V) ./ max.(abs.(V), 1e-300)) <= 1e-11, "quantiles differ from legacy_lhs_values.csv")
end

# --- P3 --------------------------------------------------------------------------------
function per_sample(sampler, n; covariances=nothing, seed=1)
    rng = StableRNG(seed)
    buf = copy(tp.center)
    t0 = time_ns()
    for _ in 1:n
        sample_time_forcings!(rng, buf, sampler; covariances=covariances)
    end
    return (time_ns() - t0) / 1e9 / n, buf
end
function check_present(buf)
    for name in TIME_FORCING_NAMES
        x = getfield(buf, name)
        if name in GP.NORMALIZE_BY_PRESENT
            check(x[end] == 1, "$name is not 1 at present")
        elseif name in GP.CENTER_AT_PRESENT
            check(x[end] == 0, "$name is not 0 at present")
        end
    end
end
n3 = jint(job, "sampler_n")
component!(w, "J", "P3"; workload="n=$n3") do
    cov = Dict{Symbol,Matrix{Float64}}()
    per_sample(iw, 20)
    per_sample(iw, 20; covariances=cov)
    per_sample(mt, 20)
    t, buf = per_sample(iw, n3)
    check_present(buf)
    record!(
        w;
        variant="J",
        component="P3",
        subcomponent="total (inverse Wishart + MvNormal)",
        workload="n=$n3",
        n=n3,
        wall_s=t,
        notes="seconds per sample (12 forcings); Bartlett draw, Σ not formed",
    )
    t, buf = per_sample(iw, n3; covariances=cov)
    check_present(buf)
    record!(
        w;
        variant="J",
        component="P3",
        subcomponent="total, covariances returned",
        workload="n=$n3",
        n=n3,
        wall_s=t,
        notes="seconds per sample (12 forcings); forms Σ = (LA)⁻ᵀ(LA)⁻¹",
    )
    t, buf = per_sample(mt, n3)
    check_present(buf)
    record!(
        w;
        variant="J",
        component="P3",
        subcomponent="total, multivariate t",
        workload="n=$n3",
        n=n3,
        wall_s=t,
        notes="seconds per sample (12 forcings); exact marginal, O(p)",
    )
    x = copy(tp.center.fR)
    k = calls_for(() -> (
        for name in TIME_FORCING_NAMES
            GP._normalize!(x, name)
        end
    ))
    t = per_call(() -> (
        for name in TIME_FORCING_NAMES
            GP._normalize!(x, name)
        end
    ), k)
    return record!(
        w;
        variant="J",
        component="P3",
        subcomponent="normalisation",
        workload="n=$n3",
        n=k,
        wall_s=t,
        notes="seconds per sample (12 forcings)",
    )
end

# --- P4 --------------------------------------------------------------------------------
for n in jints(job, "covariance_n")
    need = 2 * 8.0 * nt * nt * n * 12
    if need > jfloat(job, "memory_limit_bytes")
        record!(
            w;
            variant="J",
            component="P4",
            workload="n=$n",
            n=n,
            wall_s=NaN,
            notes="skipped by the memory guard: needs about $(round(need / 1e9; digits = 1)) GB",
        )
        continue
    end
    component!(w, "J", "P4"; workload="n=$n") do
        cov = Dict{Symbol,Matrix{Float64}}()
        rng = StableRNG(2)
        buf = copy(tp.center)
        sample_time_forcings!(rng, buf, iw; covariances=cov)
        covbuf = Float64[]
        m = measure() do
            for _ in 1:n, name in TIME_FORCING_NAMES
                append!(covbuf, vec(cov[name]))
            end
            return permutedims(reshape(covbuf, nt, nt, 12, n), (1, 2, 4, 3))
        end
        check(size(m.value) == (nt, nt, n, 12), "covariance array: bad dimensions")
        return record!(
            w,
            m;
            variant="J",
            component="P4",
            subcomponent="store accepted (append + permutedims)",
            workload="n=$n",
            n=n,
            wall_s=m.wall / n,
            alloc_bytes=m.bytes ÷ n,
            notes="seconds and bytes per sample; array $(round(sizeof(m.value) / 1e9; digits = 2)) GB",
        )
    end
end

# --- P5 --------------------------------------------------------------------------------
k = jint(job, "rng_draws")
component!(w, "J", "P5") do
    for (rname, mk) in (("StableRNG", () -> StableRNG(1)), ("Xoshiro", () -> Random.Xoshiro(1)))
        rng = mk()
        rand(rng, 10)
        randn(rng, 10)
        rand(rng, Chisq(60), 10)
        for (dname, f) in (
            ("rand", () -> rand(rng, k)),
            ("randn", () -> randn(rng, k)),
            ("rand(Chisq(60))", () -> rand(rng, Chisq(60), k)),
        )
            m = measure(f)
            record!(
                w,
                m;
                variant="J",
                component="P5",
                subcomponent="$dname $rname",
                n=k,
                wall_s=m.wall / k,
                notes="seconds per draw",
            )
        end
    end
end
