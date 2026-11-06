"""
    random_lhs(rng, n, d) -> Matrix{Float64}

Random Latin hypercube design of `n` points in `(0, 1)^d`, the algorithm of R's
`lhs::randomLHS`. For each column, a random permutation of the strata `1..n` is
jittered uniformly within each stratum: `(perm[i] − u)/n`.

Every value lies strictly inside its stratum `((k−1)/n, k/n)`, so an unbounded prior
never receives exactly 0 or 1.
"""
function random_lhs(rng::AbstractRNG, n::Integer, d::Integer)
    n >= 1 || throw(ArgumentError("n must be ≥ 1"))
    d >= 0 || throw(ArgumentError("d must be ≥ 0"))
    U = Matrix{Float64}(undef, n, d)
    for j in 1:d
        perm = randperm(rng, n)
        for i in 1:n
            k = perm[i]
            u = rand(rng)
            x = (k - u) / n
            lo = nextfloat((k - 1) / n)
            hi = prevfloat(k / n)
            U[i, j] = clamp(x, lo, hi)
        end
    end
    return U
end
