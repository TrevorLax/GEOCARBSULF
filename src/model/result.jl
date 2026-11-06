"""
    StepStatus

Outcome of one model time step.

- `Converged`: the CO2 solve converged and all checks passed.
- `NotConverged`: the CO2 solve reached `iteration_threshold` (Fortran `failed_run`).
- `NaNEncountered`: a NaN appeared inside the CO2 solve (Fortran `ISNAN` check).
- `RCO2OutOfRange`: RCO2 left `rco2_bounds` (f90:524).
- `PresentDayCheckFailed`: the present-day O2/CO2 check at t = 0 failed (f90:561).
- `InvalidState`: RCO2 is NaN although the Fortran raised no failure flag. Outputs are
  then NaN rather than Inf, exactly as in the Fortran.

For the first four failure codes, `co2` and `o2` are `+Inf` at that step and `temp` is
left as computed (the Fortran convention, finding F-08).
"""
@enum StepStatus::UInt8 begin
    Converged = 0
    NotConverged = 1
    NaNEncountered = 2
    RCO2OutOfRange = 3
    PresentDayCheckFailed = 4
    InvalidState = 5
end

"""
    GeocarbResult{T}

Output of [`run_geocarb`](@ref) on an age grid of `n` steps.

| field | units | meaning |
|:--|:--|:--|
| `age` | Myr ago | the age grid |
| `co2` | ppmv | atmospheric CO2, `250·RCO2`; `+Inf` on failed steps |
| `o2` | % | atmospheric O2, `100·O2/(O2+143)`; `+Inf` on failed steps |
| `temp` | °C | `GCM·ln(RCO2) − Ws·t/570`, the temperature change relative to the present *with the solar-luminosity term removed* (see [`temperature`](@ref)) |
| `status` | | one [`StepStatus`](@ref) per step |
| `iterations` | | CO2-solver iterations used at each step |
"""
struct GeocarbResult{T<:Real}
    age::Vector{Float64}
    co2::Vector{T}
    o2::Vector{T}
    temp::Vector{T}
    status::Vector{StepStatus}
    iterations::Vector{Int}
end

"""
    GeocarbResult{T}(age)

Pre-allocate a result for the given age grid (for [`run_geocarb!`](@ref)).
"""
function GeocarbResult{T}(age::AbstractVector{<:Real}) where {T<:Real}
    n = length(age)
    return GeocarbResult{T}(collect(Float64, age), Vector{T}(undef, n), Vector{T}(undef, n),
        Vector{T}(undef, n), fill(Converged, n), zeros(Int, n))
end

"""
    succeeded(r::GeocarbResult) -> Bool

`true` if every time step converged and passed all checks.
"""
succeeded(r::GeocarbResult) = all(==(Converged), r.status)

"""
    isfailure(s::StepStatus) -> Bool

`true` for the statuses that make the Fortran write `+Inf` into `co2` and `o2`.
"""
isfailure(s::StepStatus) = s in (NotConverged, NaNEncountered, RCO2OutOfRange, PresentDayCheckFailed)

"""
    temperature(r::GeocarbResult; T0 = 15.0, geog = nothing, Ws = nothing) -> Vector

Global mean surface temperature implied by a model run, with the conventions of the
original code made explicit (finding F-20):

- `r.temp` is `GCM·ln(RCO2) − Ws·t/570`: warming from CO2, *minus* the solar term.
- `temperature(r)` adds the present-day temperature `T0` (15 °C, Berner 2004). This
  is the quantity compared with the Mills et al. (2019) windows during precalibration
  (`lhs_sampling.R:137`).
- `temperature(r; geog = f.GEOG)` also adds the palaeogeography term. This is what
  the R analysis scripts plot as hindcasts (`analysis_and_plots.R:140`).
- `temperature(r; Ws = p.Ws)` adds the solar-luminosity term back in.
"""
function temperature(r::GeocarbResult; T0::Real = PRESENT_TEMPERATURE, geog = nothing, Ws = nothing)
    out = r.temp .+ T0
    if geog !== nothing
        length(geog) == length(out) || throw(ArgumentError("geog must have one value per time step"))
        out .+= geog
    end
    if Ws !== nothing
        out .+= Ws .* r.age ./ AGE_MAX
    end
    return out
end

function Base.show(io::IO, ::MIME"text/plain", r::GeocarbResult{T}) where {T}
    nfail = count(!=(Converged), r.status)
    println(io, "GeocarbResult{$T}: $(length(r.age)) steps, ",
        nfail == 0 ? "all converged" : "$nfail step(s) not converged/valid")
    i = lastindex(r.age)
    print(io, "  present day: CO2 = ", r.co2[i], " ppmv, O2 = ", r.o2[i], " %, temp = ", r.temp[i], " °C")
end
