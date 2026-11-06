# Single source of truth for parameter and forcing names.
#
# The order of CONSTANT_PARAMETER_NAMES is the order in which run_geocarb.f90 read
# `Matrix_56` (f90:201-256); the order of TIME_FORCING_NAMES is the column order of
# `Matrix_12` (f90:260-271). In Julia these orders only matter for flat-vector
# conversions and for calling the legacy Fortran library; everything else is by name.

"""
The 56 time-invariant GEOCARBSULFvolc parameters, in the order of the original
Fortran `Matrix_56`.
"""
const CONSTANT_PARAMETER_NAMES = (
    :ACT, :ACTcarb, :VNV, :NV, :exp_NV, :LIFE, :GYM, :FERT, :exp_fnBb, :deltaT2X,
    :GLAC, :J, :n, :Ws, :exp_fD, :Fwpa_0, :Fwsa_0, :Fwga_0, :Fwca_0, :Fmg_0, :Fmc_0,
    :Fmp_0, :Fms_0, :Fwsi_0, :Xvolc_0, :CAPd13C_0, :CAPd34S_0, :oxygen_570, :Gy_570,
    :Cy_570, :Ca_570, :Ssy_570, :Spy_570, :dlsy_570, :dlcy_570, :dlpy_570, :dlpa_570,
    :dlgy_570, :dlga_570, :Rcy_570, :Rca_570, :Rv_570, :Rg_570, :Fob, :COC, :Ga, :Ssa,
    :Spa, :ST, :dlst, :CT, :dlct, :kwpy, :kwsy, :kwgy, :kwcy,
)

"Number of time-invariant parameters (56)."
const N_CONSTANTS = length(CONSTANT_PARAMETER_NAMES)

"""
The 12 time-varying forcings, in the column order of the original Fortran `Matrix_12`.
Note that the prior CSV files list `fD` before `fAw_fA` and `RT` before `GEOG`; the R
code needed a hard-coded permutation for that (`parameterSetup.R:202`). Julia maps by name.
"""
const TIME_FORCING_NAMES = (:Sr, :d13C, :d34S, :fR, :fL, :fA, :fAw_fA, :fD, :GEOG, :RT, :fSR, :fC)

"Number of time-varying forcings (12)."
const N_FORCINGS = length(TIME_FORCING_NAMES)

const _M = "10^18 mol"
const _F = "10^18 mol/Myr"

# (description, units); descriptions are taken from the comments in run_geocarb.f90:49-119.
const PARAMETER_INFO = Dict{Symbol,Tuple{String,String}}(
    :ACT => ("Activation energy for dissolution of Mg- and Ca-silicates on land (0.03 ≈ 20 kJ/mol; 0.08 ≈ 55 kJ/mol; Berner 2004 p. 28)", "1/K"),
    :ACTcarb => ("Activation energy for dissolution of carbonates on land", "1/K"),
    :VNV => ("Rate of chemical weathering in volcanic silicate rocks relative to non-volcanic silicate rocks", "-"),
    :NV => ("Coefficient relating physical erosion to the mean 87Sr/86Sr of non-volcanic silicate rocks", "-"),
    :exp_NV => ("Exponent relating physical erosion to the mean 87Sr/86Sr of non-volcanic silicate rocks", "-"),
    :LIFE => ("Rate of chemical weathering in a minimally vegetated world relative to the present (angiosperm-dominated) world", "-"),
    :GYM => ("Rate of chemical weathering by gymnosperms relative to angiosperms", "-"),
    :FERT => ("Exponent for the fraction of vegetation whose growth is stimulated by CO2, in [2RCO2/(1+RCO2)]^FERT", "-"),
    :exp_fnBb => ("Exponent for the effect of climate on silicate or carbonate weathering in the absence of vascular plants", "-"),
    :deltaT2X => ("Climate sensitivity (warming per CO2 doubling); deltaT2X = GCM·ln(2)", "°C"),
    :GLAC => ("Factor by which deltaT2X changes during times with large continental ice sheets", "-"),
    :J => ("Coefficient in CAPd13C = CAPd13C_0 + J·(O2/38 − 1)", "per mil"),
    :n => ("Exponent in CAPd34S = CAPd34S_0·(O2/38)^n", "-"),
    :Ws => ("Effect on temperature of the linear increase in solar luminosity over time", "°C"),
    :exp_fD => ("Exponent that scales the dilution of dissolved HCO3- with runoff (fD)", "-"),
    :Fwpa_0 => ("Sulfate flux from oxidative weathering of old pyrite at present", _F),
    :Fwsa_0 => ("Sulfate flux from weathering of CaSO4 sulfur at present", _F),
    :Fwga_0 => ("Carbon flux from weathering of old sedimentary organic matter at present", _F),
    :Fwca_0 => ("Carbon flux from weathering of old Ca and Mg carbonates at present", _F),
    :Fmg_0 => ("Carbon degassing flux from volcanism, metamorphism and diagenesis of organic matter at present", _F),
    :Fmc_0 => ("Carbon degassing flux from volcanism, metamorphism and diagenesis of carbonates at present", _F),
    :Fmp_0 => ("Sulfur degassing flux from volcanism, metamorphism and diagenesis of pyrite at present", _F),
    :Fms_0 => ("Sulfur degassing flux from volcanism, metamorphism and diagenesis of CaSO4 sulfur at present", _F),
    :Fwsi_0 => ("Weathering flux for all Ca and Mg silicates at present", _F),
    :Xvolc_0 => ("Fraction of total Ca and Mg silicate weathering derived from volcanic rocks at present", "-"),
    :CAPd13C_0 => ("Carbon isotopic fractionation between shallow-marine carbonate and organic matter at present", "per mil"),
    :CAPd34S_0 => ("Sulfur isotopic fractionation between shallow-marine CaSO4 sulfur and pyrite sulfur at present", "per mil"),
    :oxygen_570 => ("Mass of atmospheric O2 at 570 Ma (7.5 and 143 correspond to 5% and 50% O2)", _M),
    :Gy_570 => ("Mass of young crustal organic carbon at 570 Ma", _M),
    :Cy_570 => ("Mass of young crustal carbonate carbon at 570 Ma", _M),
    :Ca_570 => ("Mass of old crustal carbonate carbon at 570 Ma", _M),
    :Ssy_570 => ("Mass of young CaSO4 sulfur at 570 Ma", _M),
    :Spy_570 => ("Mass of young pyrite sulfur at 570 Ma", _M),
    :dlsy_570 => ("d34S of young CaSO4 sulfur at 570 Ma", "per mil"),
    :dlcy_570 => ("d13C of young carbonate carbon at 570 Ma", "per mil"),
    :dlpy_570 => ("d34S of young pyrite sulfur at 570 Ma", "per mil"),
    :dlpa_570 => ("d34S of old pyrite sulfur at 570 Ma", "per mil"),
    :dlgy_570 => ("d13C of young organic matter at 570 Ma", "per mil"),
    :dlga_570 => ("d13C of old organic matter at 570 Ma", "per mil"),
    :Rcy_570 => ("87Sr/86Sr of young carbonates undergoing weathering at 570 Ma", "-"),
    :Rca_570 => ("87Sr/86Sr of old carbonates undergoing weathering at 570 Ma", "-"),
    :Rv_570 => ("87Sr/86Sr of sub-aerial and submarine volcanic rocks at 570 Ma", "-"),
    :Rg_570 => ("87Sr/86Sr of non-volcanic silicates at 570 Ma", "-"),
    :Fob => ("Ca and Mg flux between basalt and seawater", _F),
    :COC => ("Mass of carbon in the ocean", _M),
    :Ga => ("Mass of old crustal organic carbon", _M),
    :Ssa => ("Mass of old CaSO4 sulfur", _M),
    :Spa => ("Mass of old pyrite sulfur", _M),
    :ST => ("Mass of sulfur in oceans + interacting rocks", _M),
    :dlst => ("d34S of ST", "per mil"),
    :CT => ("Mass of carbon in oceans + interacting rocks", _M),
    :dlct => ("d13C of CT", "per mil"),
    :kwpy => ("Rate constant expressing mass dependence for young pyrite sulfur weathering", "1/Myr"),
    :kwsy => ("Rate constant expressing mass dependence for young CaSO4 sulfur weathering", "1/Myr"),
    :kwgy => ("Rate constant expressing mass dependence for young organic matter weathering", "1/Myr"),
    :kwcy => ("Rate constant expressing mass dependence for young carbonate weathering", "1/Myr"),
    # time-varying forcings
    :Sr => ("Strontium isotopic composition of shallow-marine carbonate, (87Sr/86Sr − 0.7)·10^4", "-"),
    :d13C => ("Carbon isotopic composition of shallow-marine carbonate (DLCOC in the BASIC code)", "per mil"),
    :d34S => ("Sulfur isotopic composition of shallow-marine sulfate (DLSOC in the BASIC code)", "per mil"),
    :fR => ("Effect of relief on chemical weathering relative to the present", "-"),
    :fL => ("Land area covered by carbonates relative to the present", "-"),
    :fA => ("Land area relative to the present", "-"),
    :fAw_fA => ("Fraction of land area undergoing chemical weathering (normalised to the present)", "-"),
    :fD => ("Global river runoff relative to the present, without luminosity and CO2 effects", "-"),
    :GEOG => ("Change in mean land surface temperature from palaeogeography alone (Berner 2004 p. 35)", "°C"),
    :RT => ("Coefficient of continental runoff versus temperature change, fD = 1 + RT·(T − T0)", "1/°C"),
    :fSR => ("Seafloor creation (degassing) rate relative to the present", "-"),
    :fC => ("Effect of carbonate content of subducting crust on CO2 degassing relative to the present", "-"),
)

"""
    parameter_description(name::Symbol) -> String

Physical meaning of a constant parameter or time-varying forcing.
"""
parameter_description(name::Symbol) = _info(name)[1]

"""
    parameter_units(name::Symbol) -> String

Units of a constant parameter or time-varying forcing (`"-"` for dimensionless).
"""
parameter_units(name::Symbol) = _info(name)[2]

function _info(name::Symbol)
    haskey(PARAMETER_INFO, name) ||
        throw(ArgumentError("unknown parameter or forcing name :$name"))
    return PARAMETER_INFO[name]
end

"Forcings that are divided by their present-day value after sampling (`lhs_sampling.R:108`)."
const NORMALIZE_BY_PRESENT = (:fR, :fL, :fA, :fAw_fA, :fC)

"Forcings that have their present-day value subtracted after sampling (`lhs_sampling.R:110`)."
const CENTER_AT_PRESENT = (:GEOG,)
