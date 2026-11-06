# Fortran-like elementary functions.
#
# Fortran (and C) return NaN for `x**y` when x < 0 and y is not an integer, and for
# `log(x)` when x < 0. The model relies on this: NaNs are detected with ISNAN and the
# step is flagged as failed. Julia throws a `DomainError` instead, which would abort a
# whole ensemble because of one bad sample. These helpers restore the Fortran
# behaviour.

_isint(y::AbstractFloat) = isinteger(y)
_isint(y::Integer) = true
_isint(y::Real) = y == round(y)

"""
    nanpow(x, y)

`x^y`, except that a negative `x` with a non-integer `y` returns `NaN` (as C `pow` and
Fortran `**` do) instead of throwing a `DomainError`.
"""
@inline function nanpow(x::Real, y::Real)
    if x < zero(x) && !_isint(y)
        return convert(float(promote_type(typeof(x), typeof(y))), NaN)
    end
    return x^y
end

"""
    nanlog(x)

`log(x)`, except that a negative `x` returns `NaN` instead of throwing a `DomainError`.
`nanlog(0.0) == -Inf`, as in Fortran.
"""
@inline function nanlog(x::Real)
    if x < zero(x)
        return convert(float(typeof(x)), NaN)
    end
    return log(x)
end
