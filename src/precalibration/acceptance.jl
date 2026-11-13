"""
    AcceptanceRule

Decides whether a simulation passes the precalibration. Rules are small values that
can be combined; adding an experiment does not need new engine code.

- [`OutboundRule`](@ref): % outbound of CO2 or temperature ≤ threshold;
- [`CretaceousWindowRule`](@ref): temperature inside its window at one age;
- [`AllOf`](@ref): all of several rules.

Use [`accepts`](@ref) to evaluate a rule.
"""
abstract type AcceptanceRule end

"""
    EvaluationContext(co2_windows, temp_windows; T0 = 15.0)

What the rules compare a model run against.
"""
struct EvaluationContext
    co2_windows::Windows
    temp_windows::Windows
    T0::Float64
end
EvaluationContext(co2::Windows, temp::Windows; T0::Real=PRESENT_TEMPERATURE) = EvaluationContext(co2, temp, Float64(T0))

"""
    OutboundRule(variable, threshold; reject_failed = false)

Accept if the % outbound of `variable` (`:co2` or `:temp`) is ≤ `threshold`
(`lhs_sampling.R:150-163`). A `NaN` score never passes. With `reject_failed = true`,
runs with any failed step score 1 (finding F-04).
"""
struct OutboundRule <: AcceptanceRule
    variable::Symbol
    threshold::Float64
    reject_failed::Bool
    function OutboundRule(variable::Symbol, threshold::Real; reject_failed::Bool=false)
        variable in (:co2, :temp) || throw(ArgumentError("variable must be :co2 or :temp"))
        0 < threshold <= 1 || throw(ArgumentError("threshold must be in (0, 1]"))
        return new(variable, Float64(threshold), reject_failed)
    end
end

"""
    CretaceousWindowRule(age)

Accept only if `temp + T0` lies inside the temperature window at `age` (Myr ago); see
`lhs_sampling_cret.R:136-140`. A `NaN` temperature fails. The R code used the step
index 49, which is 90 Ma on the 570:−10:0 grid (finding F-03).
"""
struct CretaceousWindowRule <: AcceptanceRule
    age::Float64
end

"""
    AllOf(rules...)

Accept if every rule accepts.
"""
struct AllOf <: AcceptanceRule
    rules::Vector{AcceptanceRule}
end
AllOf(rules::AcceptanceRule...) = AllOf(AcceptanceRule[rules...])

"""
    accepts(rule, r::GeocarbResult, ctx::EvaluationContext) -> Bool
"""
function accepts(rule::OutboundRule, r::GeocarbResult, ctx::EvaluationContext)
    w = rule.variable == :co2 ? ctx.co2_windows : ctx.temp_windows
    score = percent_outbound(r, w, rule.variable; T0=ctx.T0, reject_failed=rule.reject_failed)
    return score <= rule.threshold     # false for NaN
end

function accepts(rule::CretaceousWindowRule, r::GeocarbResult, ctx::EvaluationContext)
    i = findfirst(==(rule.age), r.age)
    i === nothing && throw(ArgumentError("no model time step at age $(rule.age) Myr ago"))
    x = r.temp[i] + ctx.T0
    return ctx.temp_windows.low[i] <= x <= ctx.temp_windows.high[i]
end

accepts(rule::AllOf, r::GeocarbResult, ctx::EvaluationContext) = all(q -> accepts(q, r, ctx), rule.rules)

"""
    build_rule(cfg::ExperimentConfig) -> AcceptanceRule

Acceptance rule described by an experiment configuration.
"""
function build_rule(cfg::ExperimentConfig)
    rules = AcceptanceRule[]
    cfg.constraint in (:co2, :both) &&
        push!(rules, OutboundRule(:co2, cfg.threshold; reject_failed=cfg.reject_failed_runs))
    cfg.constraint in (:temp, :both) &&
        push!(rules, OutboundRule(:temp, cfg.threshold; reject_failed=cfg.reject_failed_runs))
    cfg.cretaceous_age === nothing || push!(rules, CretaceousWindowRule(cfg.cretaceous_age))
    return AllOf(rules)
end
