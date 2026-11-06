# Direct calls into the compiled legacy Fortran (run_geocarb.f90 / run_geocarb_supp.f90)
# with `ccall`, bypassing R. gfortran exports `subroutine run_geocarb` as the symbol
# `run_geocarb_`; every argument is passed by reference.

using Libdl
using GeocarbPrecalibration
using GeocarbPrecalibration: forcing_matrix

"""
    find_fortran_lib(dir, name) -> Union{String,Nothing}

Path of `name.so`, `name.dll` or `name.dylib` in `dir`, if any.
"""
function find_fortran_lib(dir::AbstractString, name::AbstractString)
    for ext in (".so", ".dll", ".dylib")
        f = joinpath(dir, name * ext)
        isfile(f) && return f
    end
    return nothing
end

"""
    fortran_symbol(path, sym) -> Ptr{Cvoid} or nothing

Open a shared library and look up a symbol; `nothing` (with a warning) if that fails,
for example because the gfortran runtime DLLs are not on the PATH.
"""
function fortran_symbol(path::AbstractString, sym::Symbol)
    try
        h = Libdl.dlopen(path)
        return Libdl.dlsym(h, sym)
    catch err
        @warn "could not load $sym from $path" exception = err
        return nothing
    end
end

"""
    fortran_run(fptr, p, f; iteration_threshold = 10) -> (co2, o2, temp)

Call `run_geocarb_` with the constants in `Matrix_56` order and the forcings as the
58 × 12 `Matrix_12` the Fortran expects.
"""
function fortran_run(fptr::Ptr{Cvoid}, p::ConstantParams, f::TimeForcings; iteration_threshold::Integer = 10)
    m56 = Float64.(parameter_vector(p))
    m12 = Float64.(forcing_matrix(f))
    age = copy(f.age)
    n = length(age)
    co2 = fill(-999.99, n); o2 = fill(-999.99, n); temp = fill(-999.99, n)
    ccall(fptr, Cvoid,
          (Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ref{Int32}, Ref{Int32}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}),
          m56, m12, age, Int32(n), Int32(iteration_threshold), co2, o2, temp)
    return co2, o2, temp
end

"""
    fortran_run_supp(fptr, p, f, beg, en, gym_fac, dT2X_fac; iteration_threshold = 10) -> (co2, o2, temp)

Call `run_geocarb_supp_` (supplemental experiments).
"""
function fortran_run_supp(fptr::Ptr{Cvoid}, p::ConstantParams, f::TimeForcings, beg::Real, en::Real,
                          gym_fac::Real, dT2X_fac::Real; iteration_threshold::Integer = 10)
    m56 = Float64.(parameter_vector(p))
    m12 = Float64.(forcing_matrix(f))
    age = copy(f.age)
    n = length(age)
    co2 = fill(-999.99, n); o2 = fill(-999.99, n); temp = fill(-999.99, n)
    ccall(fptr, Cvoid,
          (Ptr{Float64}, Ptr{Float64}, Ref{Float64}, Ref{Float64}, Ref{Float64}, Ref{Float64},
           Ptr{Float64}, Ref{Int32}, Ref{Int32}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}),
          m56, m12, Float64(beg), Float64(en), Float64(gym_fac), Float64(dT2X_fac),
          age, Int32(n), Int32(iteration_threshold), co2, o2, temp)
    return co2, o2, temp
end
