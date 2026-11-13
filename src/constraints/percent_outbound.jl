"""
    legacy_percent_outbound(series, w::Windows) -> Float64

Fraction of time steps at which `series` lies outside the window, with the exact
semantics of `percent_outbound.R` (Mills et al. 2019):

- if any value is `±Inf` (a failed Fortran step), return `1.0`;
- otherwise, if any value is `NaN`, return `NaN` (R returns `NA`; a run with `NaN`
  never satisfies `≤ threshold`);
- otherwise `count(x < low | x > high) / n`.

Because the Fortran never sets temperatures to `Inf`, a temperature series of a
failed run can still score below the threshold (finding F-04). Use
[`percent_outbound`](@ref) with `reject_failed = true` to avoid that.
"""
function legacy_percent_outbound(series::AbstractVector, w::Windows)
    n = length(series)
    n == length(w) || throw(ArgumentError("series has $n values but the window has $(length(w))"))
    any(isinf, series) && return 1.0
    any(isnan, series) && return NaN
    k = 0
    @inbounds for i in 1:n
        x = series[i]
        k += (x < w.low[i]) | (x > w.high[i])
    end
    return k / n
end

"""
    percent_outbound(r::GeocarbResult, w::Windows, variable; T0 = 15.0, reject_failed = false) -> Float64

% outbound of a model run for `variable = :co2` (compared as is) or `:temp`
(compared as `r.temp .+ T0`, see [`temperature`](@ref)). With
`reject_failed = true`, any run with a failed step scores `1.0`, whatever the
variable. With `false` (the default), the result equals [`legacy_percent_outbound`](@ref).
"""
function percent_outbound(
    r::GeocarbResult, w::Windows, variable::Symbol; T0::Real=PRESENT_TEMPERATURE, reject_failed::Bool=false
)
    reject_failed && !succeeded(r) && return 1.0
    if variable == :co2
        return legacy_percent_outbound(r.co2, w)
    elseif variable == :temp
        return _legacy_percent_outbound_shifted(r.temp, T0, w)
    else
        throw(ArgumentError("variable must be :co2 or :temp, got :$variable"))
    end
end

# legacy_percent_outbound(temp .+ T0, w) without allocating
function _legacy_percent_outbound_shifted(series::AbstractVector, T0::Real, w::Windows)
    n = length(series)
    n == length(w) || throw(ArgumentError("series has $n values but the window has $(length(w))"))
    any(isinf, series) && return 1.0
    any(isnan, series) && return NaN
    k = 0
    @inbounds for i in 1:n
        x = series[i] + T0
        k += (x < w.low[i]) | (x > w.high[i])
    end
    return k / n
end
