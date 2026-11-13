"""
    bw_nrd0(x) -> Float64

Silverman's rule-of-thumb bandwidth, identical to R's `bw.nrd0`:
`0.9·min(sd, IQR/1.34)·n^(−1/5)`, with R's fallbacks for degenerate data.
"""
function bw_nrd0(x::AbstractVector{<:Real})
    length(x) >= 2 || throw(ArgumentError("need at least 2 data points"))
    hi = std(x)
    q = Statistics.quantile(x, [0.25, 0.75])
    lo = min(hi, (q[2] - q[1]) / 1.34)
    if !(lo > 0)
        lo = if hi > 0
            hi
        elseif abs(x[1]) > 0
            abs(x[1])
        else
            1.0
        end
    end
    return 0.9 * lo * length(x)^(-0.2)
end

"""
    gaussian_kde(x; from = minimum(x) - 3bw, to = maximum(x) + 3bw, n = 512, bw = bw_nrd0(x))
        -> (x = grid, density = values)

Gaussian kernel density estimate on an evenly spaced grid of `n` points, evaluated
exactly (R's `density` uses an FFT approximation of the same estimator).
"""
function gaussian_kde(
    x::AbstractVector{<:Real};
    bw::Real=bw_nrd0(x),
    from::Real=minimum(x) - 3bw,
    to::Real=maximum(x) + 3bw,
    n::Integer=512,
)
    bw > 0 || throw(ArgumentError("bandwidth must be positive"))
    from < to || throw(ArgumentError("from must be smaller than to"))
    grid = collect(range(Float64(from), Float64(to); length=n))
    dens = zeros(n)
    c = 1 / (length(x) * bw * sqrt(2π))
    for (k, g) in enumerate(grid)
        s = 0.0
        @inbounds for xi in x
            z = (g - xi) / bw
            s += exp(-0.5 * z * z)
        end
        dens[k] = c * s
    end
    return (x=grid, density=dens)
end
