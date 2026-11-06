@testset "inverse-Wishart degrees of freedom" begin
    dof = inverse_wishart_dof(TIME_PRIOR.sigma, read_variance_reduction())
    # n_time + 3 + ceil(2 max(σ²)/(1 − f)), computed independently from the CSV
    expected = Dict(:Sr => 193, :d13C => 69, :d34S => 153, :fR => 62, :fL => 63, :fA => 62, :fD => 62,
                    :fAw_fA => 63, :RT => 62, :GEOG => 74, :fSR => 62, :fC => 62)
    @test dof == expected
    @test_throws ArgumentError read_variance_reduction(tmpfile("[variance_reduction]\nSr = 0.0\n"; ext = ".toml"))
end

@testset "time-series samplers" begin
    iw = InverseWishartSampler(TIME_PRIOR)
    mt = MultivariateTSampler(TIME_PRIOR)
    f = copy(TIME_PRIOR.center)
    rng = StableRNG(11)
    sample_time_forcings!(rng, f, iw)
    @test all(getfield(f, n)[end] == 1.0 for n in G.NORMALIZE_BY_PRESENT)
    @test f.GEOG[end] == 0.0
    @test f.Sr != TIME_PRIOR.center.Sr
    @test_throws ArgumentError sample_time_forcings!(rng, f, mt; covariances = Dict{Symbol,Matrix{Float64}}())

    # covariance draws have mean diag(σ²); series have mean μ (Sr is not normalised)
    N = 400
    covs = Dict{Symbol,Matrix{Float64}}()
    acc = zeros(58, 58)
    srs = zeros(58, N)
    for k in 1:N
        sample_time_forcings!(rng, f, iw; covariances = covs)
        acc .+= covs[:Sr]
        srs[:, k] .= f.Sr
    end
    m = acc ./ N
    σ2 = TIME_PRIOR.sigma.Sr .^ 2
    @test all(isapprox(m[i, i], σ2[i]; rtol = 0.1) for i in 1:58)
    @test all(abs(m[i, j]) <= 0.1 * sqrt(σ2[i] * σ2[j]) for i in 1:58, j in 1:58 if i != j)
    @test all(abs(Statistics.mean(srs[i, :]) - TIME_PRIOR.center.Sr[i]) < 5 * sqrt(σ2[i] / N) for i in 1:58)

    # the multivariate-t sampler has the same marginals (d13C: ν = 69, the heaviest tails)
    N2 = 2000
    a = zeros(58, N2); b = zeros(58, N2)
    r1 = StableRNG(21); r2 = StableRNG(22)
    for k in 1:N2
        sample_time_forcings!(r1, f, iw); a[:, k] .= f.d13C
        sample_time_forcings!(r2, f, mt); b[:, k] .= f.d13C
    end
    for i in (1, 20, 40, 58)
        @test pvalue(ApproximateTwoSampleKSTest(a[i, :], b[i, :])) > 1e-3
    end
    s2 = TIME_PRIOR.sigma.d13C .^ 2
    @test all(isapprox(Statistics.var(b[i, :]), s2[i]; rtol = 0.2) for i in 1:58)
    @test all(isapprox(Statistics.var(a[i, :]), s2[i]; rtol = 0.2) for i in 1:58)
end
