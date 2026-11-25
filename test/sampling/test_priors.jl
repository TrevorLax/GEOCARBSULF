@testset "truncated priors" begin
    priors = build_priors(PRIOR_TABLE)
    @test length(priors) == 56
    pr = Dict(p.name => p for p in priors)
    dT = pr[:deltaT2X]
    @test dT.base isa Distributions.LogNormal
    @test dT.base.μ == log(3.0) && dT.base.σ == log(1.25)   # meanlog = log(mean), sdlog = log(two_sigma/2)
    @test dT.cdf_lower > 0 && dT.cdf_upper == 1
    @test G.quantile_from_unit(dT, 0.0) ≈ 1.5                   # bottom of the truncated range
    @test pr[:Ws].cdf_lower == 0 && pr[:Ws].cdf_upper == 1      # untruncated
    glac = pr[:GLAC]
    @test glac.base == Distributions.Normal(2.0, 0.5)           # σ = two_sigma / 2
    u = 0.3                                                     # R: qnorm(u*(F(hi)-F(lo)) + F(lo))
    @test G.quantile_from_unit(glac, u) ==
        Distributions.quantile(Distributions.Normal(2.0, 0.5), u * (glac.cdf_upper - glac.cdf_lower) + glac.cdf_lower)

    # truncation far in the tails (J-23)
    @test !any(p.upper_tail for p in priors)                    # shipped priors keep the R formula
    far = G.TruncatedPrior(:far, Distributions.Normal(0.0, 1.0), 9.0, 10.0)   # F(9) and F(10) both round to 1.0
    @test far.upper_tail && far.cdf_lower == far.cdf_upper == 1.0
    xs = [G.quantile_from_unit(far, u) for u in (1e-9, 0.25, 0.5, 0.75, 1 - 1e-9)]
    @test all(9.0 .<= xs .<= 10.0) && issorted(xs) && xs[1] < 9.001
    @test_throws ArgumentError G.TruncatedPrior(:none, Distributions.Normal(0.0, 1.0), 40.0, 50.0)   # no mass
    @test_throws ArgumentError G.TruncatedPrior(:none, Distributions.Uniform(0.0, 1.0), 2.0, 3.0)
    @test_throws ArgumentError G.TruncatedPrior(:inverted, Distributions.Normal(0.0, 1.0), 1.0, -1.0)
    @test G.quantile_from_unit(glac, 1.0) <= glac.upper && G.quantile_from_unit(glac, 0.0) >= glac.lower

    X = sample_constants(StableRNG(3), priors, 20_000)
    @test size(X) == (20_000, 56)
    @test all(all(p.lower .<= X[:, j] .<= p.upper) for (j, p) in enumerate(priors))
    for name in (:deltaT2X, :GLAC, :FERT, :Ws, :Xvolc_0, :oxygen_570)
        j = findfirst(p -> p.name == name, priors)
        ks = ApproximateOneSampleKSTest(X[:, j], G.truncated_distribution(priors[j]))
        @test pvalue(ks) > 1e-3
    end
end
