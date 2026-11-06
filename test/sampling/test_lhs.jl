@testset "random_lhs" begin
    n, d = 50, 4
    U = random_lhs(StableRNG(1), n, d)
    @test size(U) == (n, d)
    for j in 1:d                                   # exactly one point per stratum, strictly inside
        s = sort(U[:, j])
        @test all((k - 1) / n < s[k] < k / n for k in 1:n)
    end
    @test random_lhs(StableRNG(5), 10, 3) == random_lhs(StableRNG(5), 10, 3)
    @test random_lhs(StableRNG(5), 10, 3) != random_lhs(StableRNG(6), 10, 3)
    @test size(random_lhs(StableRNG(1), 1, 2)) == (1, 2)
    @test_throws ArgumentError random_lhs(StableRNG(1), 0, 2)
end
