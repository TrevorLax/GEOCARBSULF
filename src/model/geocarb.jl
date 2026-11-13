"""
    run_geocarb(p::ConstantParams, f::TimeForcings; options = ModelOptions()) -> GeocarbResult

Run GEOCARBSULFvolc from 570 Ma to the present on the age grid of `f`.

This is a line-by-line port of `fortran/src/run_geocarb.f90` (and, through
[`ModelOptions`](@ref), of `run_geocarb_supp.f90`). The model never throws because of
the parameter values: numerical failures are reported per step in `result.status`
(see [`StepStatus`](@ref)) with the Fortran output conventions (`co2 = o2 = Inf` on
failed steps). Invalid *inputs* (for example an age grid whose spacing is not
`options.dt`) raise an `ArgumentError` before the run starts.

# Examples

```jldoctest
julia> table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"));

julia> p = mean_constants(table);

julia> f = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv")).center;

julia> r = run_geocarb(p, f);

julia> succeeded(r)
true

julia> length(r.co2)   # ppmv, 58 values from 570 Ma to the present
58

julia> round.(r.co2[1:3]; sigdigits = 6)
3-element Vector{Float64}:
 5473.6
 5663.08
 6226.25

julia> round(r.co2[end]; digits = 1)   # present day
243.7
```
"""
function run_geocarb(p::ConstantParams, f::TimeForcings; options::ModelOptions=DEFAULT_MODEL_OPTIONS)
    T = promote_type(_numtype(p), _numtype(f))
    out = GeocarbResult{T}(f.age)
    return run_geocarb!(out, p, f; options=options)
end

"""
    run_geocarb!(out::GeocarbResult, p, f; options = ModelOptions()) -> out

In-place version of [`run_geocarb`](@ref): overwrite the pre-allocated `out` (see
`GeocarbResult{T}(age)`). It does not allocate, which matters inside the sampling
loop.
"""
function run_geocarb!(
    out::GeocarbResult, p::ConstantParams, f::TimeForcings; options::ModelOptions=DEFAULT_MODEL_OPTIONS
)
    o = options
    age = f.age
    n = length(age)
    length(out.co2) == n || throw(ArgumentError("output has $(length(out.co2)) steps but the forcings have $n"))
    _check_dt(age, o.dt)
    k = resolve_constants(o)
    T = promote_type(_numtype(p), _numtype(f))

    s = initial_state(T, p)
    rco2 = convert(T, RCO2_INITIAL)

    @inbounds for i in 1:n
        t = age[i]
        status = Converged

        gcm = gcm_factor(t, p, o, k)
        fE = vegetation_fE(t, p, o)
        fBB = carbonate_fBB(t, rco2, gcm, f.GEOG[i], p)

        src = source_fluxes(i, s, fE, fBB, p, f)
        capd34S, capd13C = isotope_fractionations(s.oxygen, p)
        bur = burial_fluxes(i, s, src, capd34S, capd13C, f)
        roc, _, fvolc = volcanic_weathering(i, src, bur, s, p, f, k)
        oxygen = update_oxygen(t, s.oxygen, src, bur, o.dt)
        fwsi_nc = silicate_weathering_no_climate(i, src, bur, fE, fvolc, p, f)

        rco2, status, iters = solve_rco2(t, rco2, fwsi_nc, gcm, f.RT[i], f.GEOG[i], p, o, k)
        failed = status != Converged

        # failure if CO2 < 150 ppmv or > 50 000 ppmv (f90:524)
        if rco2 < k.rco2_min || rco2 > k.rco2_max
            failed || (status = RCO2OutOfRange)
            failed = true
        end

        s = update_reservoirs(s, oxygen, src, bur, capd34S, capd13C, roc, f.d34S[i], f.d13C[i], p, o.dt)

        out.co2[i] = rco2 * PLEISTOCENE_CO2_PPM
        o2pct = 100 * (s.oxygen / (s.oxygen + O2_PERCENT_CONSTANT))
        out.o2[i] = o2pct
        out.temp[i] = gcm * nanlog(rco2) - p.Ws * t / AGE_MAX

        # present-day check on O2 (%) and RCO2 (f90:558-566)
        present_fail =
            t == 0 && (
                isnan(s.oxygen + rco2) ||
                o2pct < k.pd_o2_min ||
                o2pct > k.pd_o2_max ||
                rco2 < k.pd_rco2_min ||
                rco2 > k.pd_rco2_max
            )
        if present_fail && !failed
            status = PresentDayCheckFailed
        end
        if present_fail || failed
            out.co2[i] = Inf
            out.o2[i] = Inf
        elseif isnan(rco2)
            status = InvalidState
        end
        out.status[i] = status
        out.iterations[i] = iters
    end
    return out
end

function _check_dt(age::Vector{Float64}, dt::Float64)
    for i in 2:length(age)
        if age[i - 1] - age[i] != dt
            throw(
                ArgumentError(
                    "the age grid must have a uniform spacing of dt = $dt Myr " * "(found $(age[i-1]) → $(age[i]))"
                ),
            )
        end
    end
    return nothing
end
