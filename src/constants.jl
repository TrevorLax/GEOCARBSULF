"Directory with the input data shipped with the package (`data/`)."
const DATA_DIR = normpath(joinpath(@__DIR__, "..", "data"))

"""
    datapath(parts...) -> String

Path of a file in the package's `data/` directory, for example
`datapath("GEOCARB_input_summaries_calib_all.csv")`.
"""
datapath(parts::AbstractString...) = joinpath(DATA_DIR, parts...)

# Named constants of GEOCARBSULFvolc. Each was a bare literal in
# fortran/src/run_geocarb.f90; the line numbers below refer to that file.

"Oldest model age (Myr ago). Also the time scale of the solar-luminosity term `Ws*t/570` (f90 throughout)."
const AGE_MAX = 570.0

"Pleistocene mean atmospheric CO2 (ppmv), used to convert RCO2 to ppmv (f90:549)."
const PLEISTOCENE_CO2_PPM = 250.0

"Mass of atmospheric O2 at the present day, 10^18 mol (f90:274, `oxygen_0`)."
const O2_MASS_PRESENT = 38.0

"Constant in the conversion of O2 mass to percent, `100*O2/(O2 + 143)` (f90:550)."
const O2_PERCENT_CONSTANT = 143.0

"Present-day global mean surface temperature T0 in °C (Berner 2004, eqs. 2.8 and 2.28; `lhs_sampling.R:137`)."
const PRESENT_TEMPERATURE = 15.0

"Initial placeholder value of RCO2 (f90:276). RCO2 is solved for at every time step."
const RCO2_INITIAL = 10.0

"O2 : sulfur stoichiometry (15/8) in the oxygen mass balance (f90:404)."
const PYRITE_O2_RATIO = 15.0 / 8.0

"Scale of the Sr forcing: `Roc = Sr/10000 + 0.7` (f90:393)."
const SR_SCALE = 10000.0

"Offset of the Sr forcing: `Roc = Sr/10000 + 0.7` (f90:393)."
const SR_OFFSET = 0.7

"Start of the ramp from non-vascular plants to gymnosperms (Myr ago, f90:319-339)."
const AGE_VASCULAR_RAMP_START = 380.0

"End of the ramp to gymnosperm domination (Myr ago, f90:330-346)."
const AGE_GYMNOSPERM = 350.0

"Length of the vascular-plant ramp used for `fE` and `fBB` (Myr, f90:332-337)."
const VASCULAR_RAMP_LENGTH = 30.0

"Interval constants used to blend the silicate-weathering expressions between 380 and 350 Ma (f90:479-480; see F-10)."
const BLEND_DENOMINATOR = 31.0
const BLEND_UPPER = 381.0
