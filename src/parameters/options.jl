"""
    IntervalList <: AbstractVector{Tuple{Float64,Float64}}

Read-only list of `(lower, upper)` age intervals (the `glacial_intervals` of
[`ModelOptions`](@ref)). It behaves like a vector of pairs but cannot be modified in
place, so options shared between runs (such as the default options) cannot be changed
behind their back.
"""
struct IntervalList <: AbstractVector{Tuple{Float64,Float64}}
    data::Vector{Tuple{Float64,Float64}}
    IntervalList(itr) = new(Tuple{Float64,Float64}[_pair(g) for g in itr])
end
Base.size(v::IntervalList) = size(v.data)
Base.@propagate_inbounds Base.getindex(v::IntervalList, i::Int) = v.data[i]
Base.IndexStyle(::Type{IntervalList}) = IndexLinear()

"""
    ModelOptions(; kwargs...)

Structural options of the GEOCARBSULFvolc model. **The defaults reproduce
`fortran/src/run_geocarb.f90`, including its single-precision literals.** The supplemental experiments of
`run_geocarb_supp.f90` are expressed as options of the same model instead of a second
copy of it.

| keyword | default | meaning (Fortran reference) |
|:--|:--|:--|
| `dt` | `10.0` | time step in Myr (`Dt` in the Fortran); the age grid must have exactly this spacing |
| `glacial_intervals` | `[(260, 330), (-Inf, 40)]` | closed age intervals (Myr ago) in which `GCM = GLAC*deltaT2X/ln 2` |
| `gym_angio_transition` | `(130, 80)` | start and end of the gymnosperm → angiosperm ramp in `fE` (supp `age_gym_ang_beg/end`) |
| `gym_factor` | `1.0` | multiplier on `GYM` at the start of that ramp (supp `gym_fac`); must be > 0, because `fE` divides the mass-balance silicate weathering |
| `dT2X_ramp` | `false` | ramp ΔT2x from `deltaT2X` to `GLAC*deltaT2X` over `dT2X_ramp_interval` (supp `dT2X_fac ≥ 0`) |
| `dT2X_ramp_interval` | `(130, 40)` | ages (Myr ago) at which the ramp factor is 1 and `GLAC` |
| `iteration_threshold` | `10` | iteration at which the CO2 solve is declared failed (the R value): `N` allows `N − 1` Newton updates, so `N ≥ 2` |
| `convergence_tol` | `0.01` | stop when `abs(RCO2/RCO2_old - 1) <= tol` |
| `newton_damping` | `0.9` | damping of each Newton step |
| `newton_shrink` | `0.2` | geometric shrinkage used when a step would make RCO2 non-positive |
| `rco2_bounds` | `(0.6, 200.0)` | RCO2 outside these bounds marks the step failed (150 and 50 000 ppmv) |
| `present_day_o2_percent` | `(19.0, 23.0)` | present-day O2 (%) check |
| `present_day_rco2` | `(0.8, 1.2)` | present-day RCO2 check |
| `corrected_newton_derivative` | `false` | use the exact derivative of the non-vascular expression in the CO2 solver: in the pre-380 Ma regime and in the non-vascular part of the 380–350 Ma blend (finding F-01); `false` reproduces the Fortran |
| `report_nan_target` | `false` | report a step whose mass-balance target (`fwsi_no_climate`) is NaN as `NaNEncountered`. The Fortran reports such a step as `NotConverged` when the iteration limit comes before the shrinking RCO2 produces a NaN itself. Only the status changes; the iteration and all outputs are identical. `false` reproduces the Fortran (finding F-33) |
| `unified_vascular_blend` | `false` | blend the non-vascular and vascular CO2-solver expressions over the same 380–350 Ma interval as `fE` and `fBB` (30 Myr). `false` reproduces the Fortran, whose solver blends over 381–350 Ma (31 Myr), so at 380 Ma the solver is 1/31 vascular while `fBB` is purely non-vascular (finding F-10) |
| `fortran_single_literals` | `true` | round the decimal literals of the Fortran (`0.01, 0.9, 0.2, 0.7, 0.6, 0.8, 1.2` and `log(2.0)`) to single precision, as gfortran does (finding F-05). Only options left at their Fortran default values are rounded; a value you set (for example `convergence_tol = 1e-6`) is used exactly as given. This is what the published results were computed with, and it reproduces the compiled code to rounding error. `false` uses Float64 values instead. That is cleaner arithmetic, but it changes individual runs: in 1000 prior draws, 101 time steps (summed over all runs) switch between valid and failed and CO2 moves by up to 14 % (see `docs/src/porting_notes.md`). |

The supplemental experiment of the R code `supp_experiment_parameters = c(beg, end, gym_fac, dT2X_fac)`
corresponds to `ModelOptions(gym_angio_transition = (beg, end), gym_factor = gym_fac, dT2X_ramp = dT2X_fac >= 0)`.
Note that the R default `c(130, 80, 1, 1)` *enables* the ΔT2x ramp (finding F-09);
here the ramp is off unless asked for.

# Number types

The model is written for `Float64` inputs and for ForwardDiff dual numbers built on
`Float64` (derivatives through the whole run, including the CO2 solve). The numerical
constants of [`ResolvedConstants`](@ref GeocarbPrecalibration.ResolvedConstants) are
`Float64`, so other input types run but are not computed in their own precision:
`Float32` inputs are promoted to `Float64` inside the CO2 solve and the outputs are
stored as `Float32`, and `BigFloat` inputs are combined with constants of only
`Float64` precision.
"""
struct ModelOptions
    dt::Float64
    glacial_intervals::IntervalList
    gym_angio_transition::Tuple{Float64,Float64}
    gym_factor::Float64
    dT2X_ramp::Bool
    dT2X_ramp_interval::Tuple{Float64,Float64}
    iteration_threshold::Int
    convergence_tol::Float64
    newton_damping::Float64
    newton_shrink::Float64
    rco2_bounds::Tuple{Float64,Float64}
    present_day_o2_percent::Tuple{Float64,Float64}
    present_day_rco2::Tuple{Float64,Float64}
    corrected_newton_derivative::Bool
    fortran_single_literals::Bool
    report_nan_target::Bool
    unified_vascular_blend::Bool
end

function _pair(x)
    return (
        length(x) == 2 || throw(ArgumentError("expected a pair of numbers, got $x")); (Float64(x[1]), Float64(x[2]))
    )
end

function ModelOptions(;
    dt::Real=10.0,
    glacial_intervals=[(260.0, 330.0), (-Inf, 40.0)],
    gym_angio_transition=(130.0, 80.0),
    gym_factor::Real=1.0,
    dT2X_ramp::Bool=false,
    dT2X_ramp_interval=(130.0, 40.0),
    iteration_threshold::Integer=10,
    convergence_tol::Real=0.01,
    newton_damping::Real=0.9,
    newton_shrink::Real=0.2,
    rco2_bounds=(0.6, 200.0),
    present_day_o2_percent=(19.0, 23.0),
    present_day_rco2=(0.8, 1.2),
    corrected_newton_derivative::Bool=false,
    fortran_single_literals::Bool=true,
    report_nan_target::Bool=false,
    unified_vascular_blend::Bool=false,
)
    o = ModelOptions(
        Float64(dt),
        IntervalList(glacial_intervals),
        _pair(gym_angio_transition),
        Float64(gym_factor),
        dT2X_ramp,
        _pair(dT2X_ramp_interval),
        Int(iteration_threshold),
        Float64(convergence_tol),
        Float64(newton_damping),
        Float64(newton_shrink),
        _pair(rco2_bounds),
        _pair(present_day_o2_percent),
        _pair(present_day_rco2),
        corrected_newton_derivative,
        fortran_single_literals,
        report_nan_target,
        unified_vascular_blend,
    )
    validate_options(o)
    return o
end

"""
    validate_options(o::ModelOptions) -> o

Throw an `ArgumentError` if the options are inconsistent.
"""
function validate_options(o::ModelOptions)
    (isfinite(o.dt) && o.dt > 0) || throw(ArgumentError("dt must be positive and finite, got $(o.dt)"))
    for (lo, hi) in o.glacial_intervals
        lo <= hi || throw(ArgumentError("glacial interval ($lo, $hi) must have lower ≤ upper"))
    end
    b, e = o.gym_angio_transition
    b > e || throw(ArgumentError("gym_angio_transition must be (start, end) with start > end (Myr ago), got ($b, $e)"))
    # gym_factor = 0 makes fE = 0 at the start of the ramp, and fE divides the
    # mass-balance silicate weathering (silicate_weathering_no_climate), so every run
    # would fail there.
    (isfinite(o.gym_factor) && o.gym_factor > 0) ||
        throw(ArgumentError("gym_factor must be finite and positive, got $(o.gym_factor)"))
    a, z = o.dT2X_ramp_interval
    a > z || throw(ArgumentError("dT2X_ramp_interval must be (start, end) with start > end, got ($a, $z)"))
    # the iteration at which count == iteration_threshold is a failure, so N allows
    # N - 1 Newton updates and N = 1 could never converge (J-26)
    o.iteration_threshold >= 2 || throw(
        ArgumentError("iteration_threshold must be ≥ 2 (N allows N − 1 Newton updates), got $(o.iteration_threshold)"),
    )
    o.convergence_tol > 0 || throw(ArgumentError("convergence_tol must be positive"))
    0 < o.newton_damping <= 1 || throw(ArgumentError("newton_damping must be in (0, 1]"))
    0 < o.newton_shrink < 1 || throw(ArgumentError("newton_shrink must be in (0, 1)"))
    for (nm, (lo, hi)) in (
        ("rco2_bounds", o.rco2_bounds),
        ("present_day_o2_percent", o.present_day_o2_percent),
        ("present_day_rco2", o.present_day_rco2),
    )
        lo < hi || throw(ArgumentError("$nm must be (lower, upper) with lower < upper"))
    end
    return o
end

Base.:(==)(a::ModelOptions, b::ModelOptions) = all(getfield(a, f) == getfield(b, f) for f in fieldnames(ModelOptions))
# `isequal` matches `hash` (both distinguish 0.0 from -0.0 and treat NaN as equal), as
# Dict and Set require.
function Base.isequal(a::ModelOptions, b::ModelOptions)
    return all(isequal(getfield(a, f), getfield(b, f)) for f in fieldnames(ModelOptions))
end
function Base.hash(o::ModelOptions, h::UInt)
    return foldl((acc, f) -> hash(getfield(o, f), acc), fieldnames(ModelOptions); init=hash(:ModelOptions, h))
end

"The default options (the behaviour of `run_geocarb.f90`)."
const DEFAULT_MODEL_OPTIONS = ModelOptions()

"""
    model_options_from_dict(d::AbstractDict) -> ModelOptions

Build options from a dictionary with string or symbol keys (for example the `[model]`
table of an experiment TOML file). Unknown keys raise an `ArgumentError`.
"""
function model_options_from_dict(d::AbstractDict)
    allowed = fieldnames(ModelOptions)
    kw = Dict{Symbol,Any}()
    for (k, v) in d
        s = Symbol(k)
        s in allowed || throw(ArgumentError("unknown model option '$k'; allowed: " * join(String.(allowed), ", ")))
        kw[s] = v
    end
    return ModelOptions(; kw...)
end

"""
    options_dict(o::ModelOptions) -> Dict{String,Any}

TOML-friendly representation of the options (inverse of [`model_options_from_dict`](@ref)).
"""
function options_dict(o::ModelOptions)
    d = Dict{String,Any}()
    for f in fieldnames(ModelOptions)
        v = getfield(o, f)
        d[String(f)] = if v isa Tuple
            collect(v)
        elseif v isa IntervalList
            [collect(x) for x in v]
        else
            v
        end
    end
    return d
end

"""
    ResolvedConstants

Numerical constants actually used by the model (`ln 2`, solver tolerance and
damping, Sr offset, RCO2 bounds, present-day checks), built from a
[`ModelOptions`](@ref) by `resolve_constants`. When `fortran_single_literals = true`,
`ln 2`, the Sr offset and every option still at its Fortran default are rounded through
`Float32`, as gfortran stores default-REAL literals in single precision (finding F-05);
options set to other values are used as given. Internal; not part of the public API.
"""
struct ResolvedConstants
    ln2::Float64
    tol::Float64
    damping::Float64
    shrink::Float64
    sr_offset::Float64
    rco2_min::Float64
    rco2_max::Float64
    pd_o2_min::Float64
    pd_o2_max::Float64
    pd_rco2_min::Float64
    pd_rco2_max::Float64
end

@inline _lit(x::Float64, single::Bool) = single ? Float64(Float32(x)) : x
# A user-settable option is rounded only if it still has the Fortran default value: the
# rounding reproduces the Fortran's literals, not values chosen by the user (J-07).
@inline _lit(x::Float64, fortran_default::Float64, single::Bool) = _lit(x, single && x == fortran_default)

@inline function resolve_constants(o::ModelOptions)
    s = o.fortran_single_literals
    return ResolvedConstants(
        _lit(log(2.0), s),
        _lit(o.convergence_tol, 0.01, s),
        _lit(o.newton_damping, 0.9, s),
        _lit(o.newton_shrink, 0.2, s),
        _lit(SR_OFFSET, s),
        _lit(o.rco2_bounds[1], 0.6, s),
        _lit(o.rco2_bounds[2], 200.0, s),
        _lit(o.present_day_o2_percent[1], 19.0, s),
        _lit(o.present_day_o2_percent[2], 23.0, s),
        _lit(o.present_day_rco2[1], 0.8, s),
        _lit(o.present_day_rco2[2], 1.2, s),
    )
end
