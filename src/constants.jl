"Directory with the input data shipped with the package (`data/`)."
const DATA_DIR = normpath(joinpath(@__DIR__, "..", "data"))

"""
    datapath(parts...) -> String

Path of a file in the package's `data/` directory, for example
`datapath("GEOCARB_input_summaries_calib_all.csv")`.
"""
datapath(parts::AbstractString...) = joinpath(DATA_DIR, parts...)

# Named constants of GEOCARBSULFvolc. Each was a bare literal in
# fortran/src/run_geocarb.f90; docs/src/porting_notes.md lists where.

"Oldest model age (Myr ago). Also the time scale of the solar-luminosity term `Ws*t/570`."
const AGE_MAX = 570.0

"Pleistocene mean atmospheric CO2 (ppmv), used to convert RCO2 to ppmv."
const PLEISTOCENE_CO2_PPM = 250.0

"Mass of atmospheric O2 at the present day, 10^18 mol (`oxygen_0` in the Fortran)."
const O2_MASS_PRESENT = 38.0

"Constant in the conversion of O2 mass to percent, `100*O2/(O2 + 143)`."
const O2_PERCENT_CONSTANT = 143.0

"Present-day global mean surface temperature T0 in °C (Berner 2004, eqs. 2.8 and 2.28)."
const PRESENT_TEMPERATURE = 15.0

"Initial placeholder value of RCO2. RCO2 is solved for at every time step."
const RCO2_INITIAL = 10.0

"O2 : sulfur stoichiometry (15/8) in the oxygen mass balance."
const PYRITE_O2_RATIO = 15.0 / 8.0

"Scale of the Sr forcing: `Roc = Sr/10000 + 0.7`."
const SR_SCALE = 10000.0

"Offset of the Sr forcing: `Roc = Sr/10000 + 0.7`."
const SR_OFFSET = 0.7

"Start of the ramp from non-vascular plants to gymnosperms (Myr ago)."
const AGE_VASCULAR_RAMP_START = 380.0

"End of the ramp to gymnosperm domination (Myr ago)."
const AGE_GYMNOSPERM = 350.0

"Length of the vascular-plant ramp used for `fE` and `fBB` (Myr)."
const VASCULAR_RAMP_LENGTH = 30.0

"""
Length (Myr) of the interval over which the Fortran CO2 solver blends the non-vascular
and vascular silicate-weathering expressions. It is 31, not the 30 of
`fE` and `fBB` (finding F-10); see `ModelOptions(unified_vascular_blend = true)`.
"""
const BLEND_DENOMINATOR = 31.0

"""
Upper end (Myr ago) of the CO2 solver's blending interval: the vascular
weight is `(BLEND_UPPER − t)/BLEND_DENOMINATOR`. It is 381, not the 380 used by `fE`
and `fBB`, so at 380 Ma the solver is already 1/31 vascular (finding F-10).
"""
const BLEND_UPPER = 381.0
