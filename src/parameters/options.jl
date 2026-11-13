"""
    ModelOptions(; kwargs...)

Structural options of the GEOCARBSULFvolc model. **The defaults reproduce
`fortran/src/run_geocarb.f90`, including its single-precision literals.** The supplemental experiments of
`run_geocarb_supp.f90` are expressed as options of the same model instead of a second
copy of it.

| keyword | default | meaning (Fortran reference) |
|:--|:--|:--|
| `dt` | `10.0` | time step in Myr (`Dt`, f90:273); the age grid must have exactly this spacing |
| `glacial_intervals` | `[(260, 330), (-Inf, 40)]` | closed age intervals (Myr ago) in which `GCM = GLAC*deltaT2X/ln 2` (f90:309) |
| `gym_angio_transition` | `(130, 80)` | start and end of the gymnosperm → angiosperm ramp in `fE` (supp `age_gym_ang_beg/end`) |
| `gym_factor` | `1.0` | multiplier on `GYM` during that ramp (supp `gym_fac`) |
| `dT2X_ramp` | `false` | ramp ΔT2x from `deltaT2X` to `GLAC*deltaT2X` over `dT2X_ramp_interval` (supp `dT2X_fac ≥ 0`) |
| `dT2X_ramp_interval` | `(130, 40)` | ages (Myr ago) at which the ramp factor is 1 and `GLAC` |
| `iteration_threshold` | `10` | iteration at which the CO2 solve is declared failed (`parameterSetup.R:15`) |
| `convergence_tol` | `0.01` | stop when `abs(RCO2/RCO2_old - 1) <= tol` (f90:435) |
| `newton_damping` | `0.9` | damping of each Newton step (f90:450) |
| `newton_shrink` | `0.2` | geometric shrinkage used when a step would make RCO2 non-positive (f90:452) |
| `rco2_bounds` | `(0.6, 200.0)` | RCO2 outside these bounds marks the step failed (150 and 50 000 ppmv; f90:524) |
| `present_day_o2_percent` | `(19.0, 23.0)` | present-day O2 (%) check (f90:561) |
| `present_day_rco2` | `(0.8, 1.2)` | present-day RCO2 check (f90:562) |
| `corrected_newton_derivative` | `false` | use the exact derivative in the pre-380 Ma regime (finding F-01); `false` reproduces the Fortran |
| `fortran_single_literals` | `true` | round the decimal literals of the Fortran (`0.01, 0.9, 0.2, 0.7, 0.6, 0.8, 1.2` and `log(2.0)`) to single precision, as gfortran does (finding F-05). This is what the published results were computed with, and it reproduces the compiled code to rounding error. `false` uses Float64 values instead. That is cleaner arithmetic, but it changes individual runs: in 1000 prior draws, 101 pass/fail decisions flip and CO2 moves by up to 14 % (see `docs/src/porting_notes.md`). |

The supplemental experiment of the R code `supp_experiment_parameters = c(beg, end, gym_fac, dT2X_fac)`
corresponds to `ModelOptions(gym_angio_transition = (beg, end), gym_factor = gym_fac, dT2X_ramp = dT2X_fac >= 0)`.
Note that the R default `c(130, 80, 1, 1)` *enables* the ΔT2x ramp (finding F-09);
here the ramp is off unless asked for.
"""
struct ModelOptions
    dt::Float64
    glacial_intervals::Vector{Tuple{Float64,Float64}}
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
)
    gi = Tuple{Float64,Float64}[_pair(g) for g in glacial_intervals]
    o = ModelOptions(
        Float64(dt),
        gi,
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
    )
    validate(o)
    return o
end

"""
    validate(o::ModelOptions) -> o

Throw an `ArgumentError` if the options are inconsistent.
"""
function validate(o::ModelOptions)
    (isfinite(o.dt) && o.dt > 0) || throw(ArgumentError("dt must be positive and finite, got $(o.dt)"))
    for (lo, hi) in o.glacial_intervals
        lo <= hi || throw(ArgumentError("glacial interval ($lo, $hi) must have lower ≤ upper"))
    end
    b, e = o.gym_angio_transition
    b > e || throw(ArgumentError("gym_angio_transition must be (start, end) with start > end (Myr ago), got ($b, $e)"))
    (isfinite(o.gym_factor) && o.gym_factor >= 0) ||
        throw(ArgumentError("gym_factor must be finite and non-negative, got $(o.gym_factor)"))
    a, z = o.dT2X_ramp_interval
    a > z || throw(ArgumentError("dT2X_ramp_interval must be (start, end) with start > end, got ($a, $z)"))
    o.iteration_threshold >= 1 || throw(ArgumentError("iteration_threshold must be ≥ 1"))
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
        elseif v isa AbstractVector
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
[`ModelOptions`](@ref) by `resolve_constants`. When `fortran_single_literals = true`
each value is rounded through `Float32`, as gfortran stores default-REAL literals in
single precision (finding F-05). Internal; not part of the public API.
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

@inline function resolve_constants(o::ModelOptions)
    s = o.fortran_single_literals
    return ResolvedConstants(
        _lit(log(2.0), s),
        _lit(o.convergence_tol, s),
        _lit(o.newton_damping, s),
        _lit(o.newton_shrink, s),
        _lit(SR_OFFSET, s),
        _lit(o.rco2_bounds[1], s),
        _lit(o.rco2_bounds[2], s),
        _lit(o.present_day_o2_percent[1], s),
        _lit(o.present_day_o2_percent[2], s),
        _lit(o.present_day_rco2[1], s),
        _lit(o.present_day_rco2[2], s),
    )
end
