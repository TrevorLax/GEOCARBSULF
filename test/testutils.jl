# Shared helpers for the test suite.

# StableRNGs, Distributions and Statistics are dependencies of the package; reach them
# through it so that the test environment needs no extra entries.
using GeocarbPrecalibration: datapath, StableRNG, Distributions, Statistics

const PRIOR_FILE = datapath("GEOCARB_input_summaries_calib_all.csv")
const ARRAY_FILE = datapath("GEOCARB_input_arrays_NewDegassing.csv")
const PROXY_FILE = datapath("CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv")
const TEMP_FILE = datapath("Mills_GR_2019_temp_co2.csv")

const PRIOR_TABLE = read_prior_table(PRIOR_FILE)
const TIME_PRIOR = read_time_arrays(ARRAY_FILE)

"Constants at their prior means and forcings at their centres."
default_inputs() = (mean_constants(PRIOR_TABLE), copy(TIME_PRIOR.center))

"`n` random (constants, forcings) pairs drawn from the priors with a fixed seed."
function random_inputs(n::Integer; seed = 2024, sampler = InverseWishartSampler(TIME_PRIOR))
    rng = StableRNG(seed)
    priors = build_priors(PRIOR_TABLE)
    X = sample_constants(rng, priors, n)
    names = [p.name for p in priors]
    base = parameter_vector(mean_constants(PRIOR_TABLE))
    out = Tuple{ConstantParams{Float64},TimeForcings{Float64}}[]
    for i in 1:n
        v = copy(base)
        for (j, nm) in enumerate(names)
            v[findfirst(==(nm), CONSTANT_PARAMETER_NAMES)] = X[i, j]
        end
        f = copy(TIME_PRIOR.center)
        sample_time_forcings!(rng, f, sampler)
        push!(out, (ConstantParams(collect(CONSTANT_PARAMETER_NAMES), v), f))
    end
    return out
end

"Temporary file with the given content."
function tmpfile(content::Union{AbstractString,AbstractVector{UInt8}}; ext = ".csv")
    path, io = mktemp()
    write(io, content)
    close(io)
    newpath = path * ext
    mv(path, newpath; force = true)
    return newpath
end

"A small experiment configuration for workflow tests."
small_config(; kwargs...) = ExperimentConfig(; name = "test", tag = "test", n_sample = 60, n_per_chunk = 20,
    n_accept_min = 10_000, threshold = 1.0, seed = 7, kwargs...)
