"""
    TemperatureData

Global temperature reconstruction of Mills et al. (2019, Gondwana Research): `time` in
Ma (≤ 0, i.e. negative ages), CO2 bounds (ppmv) and temperature maximum, minimum and
average (°C).
"""
struct TemperatureData
    time::Vector{Float64}
    co2_max::Vector{Float64}
    co2_min::Vector{Float64}
    T_max::Vector{Float64}
    T_min::Vector{Float64}
    T_avg::Vector{Float64}
end

"""
    read_temperature_data(path) -> TemperatureData

Read `Mills_GR_2019_temp_co2.csv`. As in `constraints.R:52`, the six columns are
taken by position: time, CO2 max, CO2 min, T max, T min, T average. Empty cells become
`NaN`.
"""
function read_temperature_data(path::AbstractString)
    t = read_csv_table(path)
    length(t.header) >= 6 || throw(ArgumentError("$path: expected at least 6 columns"))
    cols = [numeric_column(t, j; allow_missing = true) for j in 1:6]
    any(isnan, cols[1]) && throw(ArgumentError("$path: the time column has missing values"))
    return TemperatureData(cols...)
end

"""
    read_park_royer_2011(path) -> NamedTuple

Read `ParkRoyer2011_Fig3_85varred.csv` (Park & Royer 2011, Fig. 3: distribution of
ΔT2x). Returns `(deltaT2X, pdf, cdf)`. The file has CR-only line endings and a
byte-order mark, both handled by [`read_csv_table`](@ref).
"""
function read_park_royer_2011(path::AbstractString)
    t = read_csv_table(path)
    length(t.header) >= 4 || throw(ArgumentError("$path: expected 4 columns"))
    return (deltaT2X = numeric_column(t, 1), pdf = numeric_column(t, 3), cdf = numeric_column(t, 4))
end
