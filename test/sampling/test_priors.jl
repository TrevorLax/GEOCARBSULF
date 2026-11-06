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

    X = sample_constants(StableRNG(3), priors, 20_000)
    @test size(X) == (20_000, 56)
    @test all(all(p.lower .<= X[:, j] .<= p.upper) for (j, p) in enumerate(priors))
    for name in (:deltaT2X, :GLAC, :FERT, :Ws, :Xvolc_0, :oxygen_570)
        j = findfirst(p -> p.name == name, priors)
        ks = ApproximateOneSampleKSTest(X[:, j], G.truncated_distribution(priors[j]))
        @test pvalue(ks) > 1e-3
    end
end
