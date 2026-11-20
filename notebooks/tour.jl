# # GeocarbPrecalibration.jl: a guided tour
#
# *The GEOCARBSULFvolc long-term carbon-cycle model in Julia: what it is, how to set
# it up and run it, and the evidence that it reproduces the original R/Fortran code.*
#
#md # > This page is generated from `notebooks/tour.jl` with Literate.jl. The code is
#md # > shown but **not run** here, so there are no figures. To see the outputs, download
#md # > [the notebook](https://github.com/TrevorLax/GEOCARBSULF/blob/main/notebooks/GeocarbPrecalibration_tour.ipynb)
#md # > and run it as described under *Setup*.
#md #
#nb # > This notebook is generated from `notebooks/tour.jl` with Literate.jl; edit that
#nb # > file, not the `.ipynb`, and regenerate with `julia --project=notebooks notebooks/build.jl`.
#nb #
# ### How to read this notebook
#
# | if you are | read |
# |:--|:--|
# | new to the package | *Setup* and *Part 1* |
# | reviewing the software (for example for JOSS) | *Setup*, *Part 1* and *Part 2* |
# | examining the port from R/Fortran to Julia | *Part 2*; section 2.1 says what "the same answer" means |
#
# **Contents**
#
# - **Setup**: installing, opening the notebook, checking this machine
# - **Part 1, the package and the model**: 1.1 the science · 1.2 the package · 1.3 the
#   model · 1.4 inputs · 1.5 a first run · 1.6 climate sensitivity · 1.7 failed steps ·
#   1.8 options and supplemental experiments · 1.9 single-precision literals · 1.10
#   windows and % outbound · 1.11 a small precalibration · 1.12 its results · 1.13
#   going further
# - **Part 2, verification against the original code**: 2.1 what "the same answer"
#   means · 2.2 three levels of evidence · 2.3 the test suite · 2.4 level A · 2.5 level B
#   · 2.6 level C · 2.7 verdict · 2.8 reproducibility record

# ## Setup
#
# ### Installing (once)
#
# 1. **Julia.** Install [juliaup](https://github.com/JuliaLang/juliaup), the official
#    Julia installer, then Julia 1.12:
#    - Windows: `winget install --name Julia --id 9NJNWW8PVKMN -e -s msstore`
#    - macOS and Linux: `curl -fsSL https://install.julialang.org | sh`
#    - then, in a new terminal: `juliaup add 1.12` and `juliaup default 1.12`
# 2. **The repository.** `git clone https://github.com/TrevorLax/GEOCARBSULF.git` and
#    change into the new folder.
# 3. **The notebook environment.** From the repository folder run
#    `julia notebooks/setup.jl`. It instantiates the package environment (used by the
#    test cells), creates the separate notebook environment in `notebooks/` with the
#    package, CairoMakie, IJulia and Literate, precompiles everything, installs a
#    Jupyter kernel called *GeocarbPrecalibration* that starts Julia with all CPU
#    threads, and writes `notebooks/GeocarbPrecalibration_tour.ipynb`. The first run
#    takes roughly 5 to 15 minutes, mostly precompiling CairoMakie.
# 4. **Opening the notebook.** Any Jupyter front end works:
#    - JupyterLab, if you have it: `jupyter lab notebooks/GeocarbPrecalibration_tour.ipynb`;
#    - VS Code with the Jupyter extension: open the `.ipynb` file;
#    - without either: `julia --project=notebooks -e "using IJulia; jupyterlab(dir=pwd())"`
#      (IJulia offers to install a private copy of Jupyter the first time).
#
#    Choose the kernel **GeocarbPrecalibration** and run the cells from top to bottom
#    (in JupyterLab: *Run → Run All Cells*).
#
# **Optional, only for level C of Part 2** (a live run of the original code):
#
# - **R** ≥ 4.1 (the comparison was last run with R 4.6.1), with the packages
#   `lhs`, `CholWishart` and `abind` (`MASS` ships with R). In R:
#   `install.packages(c("lhs", "CholWishart", "abind"))`.
# - **A Fortran compiler** that R can use, to compile the original Fortran:
#   - Windows: [Rtools](https://cran.r-project.org/bin/windows/Rtools/) matching your R version;
#   - macOS: the gfortran build linked from [mac.r-project.org/tools](https://mac.r-project.org/tools/);
#   - Linux: your distribution's `gfortran` package (for example `sudo apt install gfortran r-base`).
#
# > ⚠️ **CairoMakie is slow the first time.** Loading CairoMakie and drawing the first
# > figure can take **several minutes** in a fresh environment (Julia compiles the
# > plotting code once, then caches it). Later figures, and later sessions, are fast.
# > The first code cell below is the slow one; let it finish.
#
# > ⚠️ **Level C needs R and gfortran.** Without R (with the packages above) and a
# > Fortran compiler, or already compiled libraries in `legacy/fortran`, the notebook
# > skips level C and says why. Levels A and B never need R.

using GeocarbPrecalibration
using CairoMakie  # loading a Makie backend also loads the package's plotting extension
include(joinpath(pkgdir(GeocarbPrecalibration), "notebooks", "tour_helpers.jl"))
set_tour_theme!()
julia_version_check()

# The helpers loaded above (`notebooks/tour_helpers.jl`) only present results: they
# run the test suite in subprocesses, load the repository's own comparison code, and
# draw tables and figures. None of them contains model code.
#
# ### Settings
#
# Edit and re-run this cell to change what the notebook does. `FAST` is the quick mode
# used by the automated test of this notebook (`notebooks/test_notebook.jl`).

FAST = get(ENV, "GEOCARB_NOTEBOOK_FAST", "false") == "true"
TEST_GROUPS = FAST ? ["constraints", "regression"] : DEFAULT_GROUPS  # test groups run in Part 2
RUN_LEVEL_B = true    # replay stored R exports, if this machine has any
RUN_LEVEL_C = :auto   # :auto = run if R and a Fortran compiler are found; true or false to force
N_DRAWS = FAST ? 100 : 400  # random prior draws used in Part 1
println("quick mode: ", FAST, " · Julia threads: ", Threads.nthreads())

# ### This machine
#
# What the notebook found. The last five rows decide whether levels B and C of Part 2
# can run.

env = detect_environment()
environment_table(env)

# ## Part 1: the package and the model
#
# ### 1.1 The science in brief
#
# Over millions of years, the amount of CO₂ in the atmosphere is set by a slow balance.
# Volcanism and metamorphism release carbon from the solid Earth. Chemical weathering
# of silicate rocks on land removes it, and the carbon ends up buried in carbonate
# rocks and in organic matter in sediments. Weathering speeds up when the climate is
# warmer and wetter, so this balance acts as a **thermostat**: if CO₂ rises, the planet
# warms, weathering accelerates and draws CO₂ down again.
#
# The **GEOCARB** family of models (Berner 2004, 2006, 2008; Royer et al. 2014) turns
# this idea into a budget of carbon and sulfur reservoirs from 570 million years ago
# (Ma) to the present, in 10-million-year steps. At each step the model solves for the
# CO₂ level at which weathering balances the carbon that must be removed. It also
# tracks atmospheric O₂ and isotope ratios.
#
# One parameter, **ΔT2x**, is the warming per doubling of CO₂. Over these time scales
# it includes slow feedbacks such as ice sheets and vegetation, so it measures
# *Earth-system sensitivity*. Another, **GLAC**, scales it during glacial periods.
#
# **Precalibration** (Wong et al. 2021, *Nature Communications* 12, 3173) asks which
# combinations of the uncertain parameters give model histories consistent with the
# geological record. It draws many parameter sets from their prior distributions, runs
# the model for each, and keeps those whose CO₂ and temperature stay inside
# observational *windows* (built from CO₂ proxies and a temperature reconstruction)
# often enough. The kept samples constrain ΔT2x.
#
# ### 1.2 What this package is
#
# `GeocarbPrecalibration.jl` is a Julia port of the R/Fortran code of Wong et al.
# (2021) (`GEOCARB-precalibration`, by Tony Wong and Ying Cui). The original code is
# kept, unmodified, in `legacy/` and is used as the test oracle in Part 2.
#
# | layer | folder | what it does |
# |:--|:--|:--|
# | parameters | `src/parameters/` | named constants, forcings and model options |
# | model | `src/model/` | `run_geocarb`, a line-by-line port of `run_geocarb.f90` |
# | inputs | `src/io/` | readers for the prior table, forcing arrays, proxies, temperatures |
# | priors and samplers | `src/priors/`, `src/sampling/` | truncated priors, Latin hypercube, inverse-Wishart forcing samples |
# | constraints | `src/constraints/` | CO₂ and temperature windows, % outbound |
# | precalibration | `src/precalibration/` | experiment files, acceptance rules, the chunked threaded engine |
# | analysis and plots | `src/analysis/`, `ext/` | the paper's summaries; figures with Makie |
#
# Compared with the original:
#
# - **experiments are TOML files** (`experiments/`) instead of edited scripts;
# - **model variants are options** (`ModelOptions`) instead of a second copy of the Fortran;
# - **runs never crash** on bad parameter values: every time step gets a status;
# - **ensembles are deterministic** whatever the number of threads, and can be checkpointed;
# - **everything is tested**, including against the original code (Part 2).
#
# ### 1.3 The model
#
# A sketch of the carbon budget the model keeps (sulfur, oxygen and strontium are
# tracked alongside):

plot_carbon_cycle_schematic()

# Each 10-million-year step runs these functions in order, each a direct port of a
# few lines of the Fortran:
#
# | step | Julia function | `run_geocarb.f90` lines |
# |:--|:--|:--|
# | climate sensitivity factor (glacial intervals, optional ΔT2x ramp) | `gcm_factor` | 309–315 |
# | effect of plants on weathering | `vegetation_fE`, `carbonate_fBB` | 319–359 |
# | weathering and degassing fluxes | `source_fluxes` | 363–378 |
# | isotope fractionation and burial | `isotope_fractionations`, `burial_fluxes` | 381–390 |
# | weathering of volcanic rocks (Sr isotopes) | `volcanic_weathering` | 393–400 |
# | atmospheric O₂ | `update_oxygen` | 403–405 |
# | silicate weathering required by mass balance | `silicate_weathering_no_climate` | 416 |
# | damped Newton solve for CO₂ | `solve_rco2` | 431–521 |
# | reservoir and isotope updates | `update_reservoirs` | 529–545 |
# | outputs and failure checks | `run_geocarb!` | 547–566 |
#
# ### 1.4 Inputs
#
# The model has **56 constant parameters** and **12 time-varying forcings**. Their
# priors come with the package, in `data/`. The prior file says which constants are
# calibrated (drawn from their prior) and which stay fixed at their mean; the table
# lists the calibrated ones of `GEOCARB_input_summaries_calib_all.csv`, the file used
# throughout.

table = read_prior_table(PRIOR_FILE)
tprior = read_time_arrays(ARRAY_FILE)
prior_table_html(table)

# The forcings are time series: for example `fSR`, the seafloor spreading rate (which
# sets volcanic degassing), `fR` (relief), `fA` (land area) and `GEOG` (temperature
# change from palaeogeography). Each has a centre and an uncertainty at every step:

plot_forcings(tprior)

# ### 1.5 A first run
#
# `run_geocarb` takes the constants and the forcings and returns CO₂ (ppmv), O₂ (%),
# a temperature and a status for each step. Here everything is at its prior mean:

p = mean_constants(table)
f = tprior.center
r = run_geocarb(p, f)

#-

plot_runs(["prior means" => r])

# The temperature drawn is `temperature(r)`, which is the model's `temp` plus 15 °C.
# That is the quantity compared with the temperature windows in precalibration. The
# documentation page *Temperature conventions* explains the other variants.
#
# ### 1.6 Climate sensitivity
#
# `update` returns a copy of the constants with some values changed. Here ΔT2x goes
# from 1.5 to 6 °C per doubling:

runs = ["ΔT2x = $(x) °C" => run_geocarb(update(p; deltaT2X=x), f) for x in (1.5, 3.0, 4.5, 6.0)]
plot_runs(runs)

# Weathering responds to temperature, and temperature responds to CO₂ through ΔT2x.
# With a more sensitive climate, a smaller change in CO₂ moves the temperature, and so
# the weathering rate, far enough to balance the carbon budget. Compare how much the
# CO₂ histories and the temperature histories spread as ΔT2x changes: the two records
# respond to ΔT2x differently, which is why Wong et al. (2021) use CO₂ proxies and a
# temperature reconstruction together.
#
# ### 1.7 When a step fails
#
# The CO₂ solver can fail for some parameter values: it does not converge, produces a
# NaN, or leaves the allowed CO₂ range. The original Fortran then writes `Inf` into
# CO₂ and O₂ for that step **and keeps integrating** from that invalid state (finding
# F-08 of the porting review). The Julia port keeps this behaviour so that results
# match, and records why each step failed in `r.status`.
#
# How often does that happen? Run the model on random draws from the priors (constants
# by Latin hypercube, forcings by the inverse-Wishart sampler of the precalibration):

draws = prior_draws(N_DRAWS)
results = [run_geocarb(q, g) for (q, g) in draws]
callout(
    :note,
    "$(count(succeeded, results)) of $(length(results)) random prior draws have every step valid; " *
    "the rest fail at one step or more.",
)

#-

plot_step_status(results; title="Step status of $(length(results)) random prior draws")

# Most prior draws fail somewhere (of the 1000 draws of the original R code compared
# in Part 2, only 6 have every step valid), which is one reason precalibration rejects
# so many samples. It also matters in Part 2: **after** a failed step the legacy model works
# with invalid numbers, so tiny rounding differences grow there. That is why the
# comparison is judged separately before and after a run's first failed step.
#
# ### 1.8 Options and the supplemental experiments
#
# The original code had a second Fortran file, `run_geocarb_supp.f90`, for the
# supplemental experiments of the paper. In Julia they are options of the one model:
#
# | experiment | `ModelOptions` |
# |:--|:--|
# | control | defaults |
# | gym | `gym_factor = 0.25` |
# | timing | `gym_angio_transition = (110, 60)` |
# | gym + timing | both |
# | ΔT2x ramp | `dT2X_ramp = true` |
# | gym + timing + ΔT2x ramp | all three |

opts = ModelOptions(; gym_angio_transition=(110, 60), gym_factor=0.25, dT2X_ramp=true)
plot_runs(["defaults" => r, "gym + timing + ΔT2x ramp" => run_geocarb(p, f; options=opts)])

# What the gymnosperm options change: the weathering factor of plants, `fE`, over
# time (a figure from the package's plotting extension).

plot_gym_modification()

# ### 1.9 A case study: single-precision literals (finding F-05)
#
# The compiled Fortran stores decimal constants such as `0.01`, `0.9` and `log(2.0)` in
# **single** precision, because that is what gfortran does with default `REAL`
# literals. Using the "cleaner" double-precision values would seem harmless. It is not:

results64 = [run_geocarb(q, g; options=ModelOptions(; fortran_single_literals=false)) for (q, g) in draws]
plot_literal_effect(results, results64)

# Some runs change from pass to fail or back, and valid steps move by far more than
# rounding error. In the 1000-sample comparison with the original code (Part 2), 101
# runs flipped and CO₂ moved by up to 14 % in otherwise valid steps. So the port reproduces the single-precision literals by default
# (`fortran_single_literals = true`), and `false` is documented as a model change, not
# a precision improvement.
#
# ### 1.10 Windows and % outbound
#
# Precalibration compares each run with windows at every step:
#
# - **CO₂ windows** come from the proxy compilation of Foster et al. (2017): at each
#   step, the envelope of the proxies within ±5 Myr and their uncertainties;
# - **temperature windows** come from the reconstruction of Mills et al. (2019).

proxy = read_proxy_data(PROXY_FILE)
cw = co2_windows(proxy, f.age)
tw = temperature_windows(read_temperature_data(TEMP_FILE), f.age)
plot_co2_windows_and_proxies(proxy, cw)

# The run at the prior means, against both windows:

plot_runs(["prior means" => r]; cw, tw)

# The **% outbound** is the fraction of steps outside the window. For CO₂ a failed
# step makes it 1, because CO₂ is `Inf` there; temperature is not set to `Inf` on
# failed steps, so its % outbound is unaffected (finding F-04). An experiment accepts
# a run if its % outbound is at most a threshold, for CO₂, temperature or both.

callout(
    :note,
    @sprintf(
        "At the prior means: %.0f %% of steps outside the CO₂ windows, %.0f %% outside the temperature windows.",
        100 * legacy_percent_outbound(r.co2, cw),
        100 * percent_outbound(r, tw, :temp)
    ),
)

# ### 1.11 A small precalibration
#
# Experiments are TOML files. `experiments/example_small.toml` is a quick one: up to
# 20 000 simulations, stopping once 1000 runs are accepted with at most 50 % outbound
# for both CO₂ and temperature:

print(read(joinpath(ROOT, "experiments", "example_small.toml"), String))

# Its `output_dir` is `results/example` inside the repository. The notebook points it
# at a temporary folder instead, so running the notebook never writes into the
# repository. (In quick mode the experiment is also made smaller.)

cfg = only(load_experiments(joinpath(ROOT, "experiments", "example_small.toml")))
quick = FAST ? (; n_sample=6_000, n_per_chunk=1_000, n_accept_min=150) : (;)
cfg = with_overrides(cfg; output_dir=mktempdir(), quick...)
println("results will be written to ", joinpath(cfg.output_dir, cfg.tag))

# `run_precalibration` runs the chunks in parallel on all threads of this session. The
# result does not depend on the number of threads: each chunk has its own random
# stream, and chunks are combined in order. This takes about a minute.

res = run_precalibration(cfg)

#-

resdir = joinpath(cfg.output_dir, cfg.tag)
save_result(joinpath(resdir, "result.jld2"), res)
written = write_summary_csvs(resdir, res)
println("saved:\n  ", join(vcat(joinpath(resdir, "result.jld2"), written), "\n  "))

# ### 1.12 Its results
#
# The headline numbers of the paper are quantiles of ΔT2x and of the glacial
# sensitivity ΔT2x·GLAC over the accepted samples:

if n_accepted(res) > 0
    tbl, exceed = sensitivity_table(res)
    display(tbl)
    callout(:note, exceed)
else
    callout(:warn, "No sample was accepted; increase `n_sample` in the cell above.")
end

# Prior and posterior of ΔT2x, with the estimate of Park & Royer (2011) for comparison:

if n_accepted(res) > 0
    dT2X_prior = only(filter(q -> q.name == :deltaT2X, build_priors(table)))
    park_royer = read_park_royer_2011(datapath("ParkRoyer2011_Fig3_85varred.csv"))
    plot_deltaT2X_distributions(res; prior=dT2X_prior, park_royer)
end

# The accepted runs (bands: 50, 90 and 95 % ranges) against the CO₂ proxies and the
# temperature windows:

n_accepted(res) > 0 ? plot_model_vs_proxy(res, proxy, tw) : callout(:warn, "No accepted samples to plot.")

# > ℹ️ **Note.** This is a small demonstration, not the paper's result: the paper's
# > experiments use far more simulations and several thresholds (see
# > `experiments/main/grid.toml`). The commands below reproduce them.
#
# ### 1.13 Going further
#
# - **Reproduce the paper**, from the repository folder (use `-t auto` for all threads):
#   - `julia --project=. -t auto scripts/run_experiment.jl experiments/main/grid.toml`
#   - `julia --project=. -t auto scripts/run_experiment.jl experiments/main/ct_out30_extra_seeds.toml`
#   - the five files in `experiments/supplemental/` and the two in `experiments/cretaceous/`
#   - then `scripts/analysis_main.jl`, `scripts/analysis_supplemental.jl` and `scripts/analysis_cretaceous.jl`
# - `--dry-run` checks a configuration quickly; `--checkpoint` makes long runs resumable.
# - **Write your own experiment**: copy a TOML file and change `constraint`,
#   `threshold`, `n_sample`, `seed` or the `[model]` table (any `ModelOptions` keyword).
# - **Documentation**: the pages *The model*, *Precalibration*, *Experiments* and
#   *Porting notes* of the package documentation.

# ## Part 2: verification against the original R/Fortran code
#
# ### 2.1 What "the same answer" means
#
# The Julia model is a line-by-line port, but its numbers cannot be **bit-for-bit**
# identical to the Fortran's. Julia's `exp`, `log` and `^` and the C library that
# gfortran uses occasionally round the last bit of a result differently. Even two
# builds of the same Fortran (the main and supplemental libraries) differ by up to
# 8e-10 for that reason. So agreement is judged with tolerances, read here from
# `test/tolerances.toml`, the single file both Fortran tests use:

tol = read_tolerances()
html_table(
    ["check", "requirement"],
    [
        ["positions of Inf and NaN (which steps fail)", "identical"],
        ["% outbound (decides acceptance)", "identical"],
        ["values before a run's first failed step", "relative difference ≤ " * fmt(tol.rtol_clean)],
        ["values at or after a run's first failed step", "relative difference ≤ " * fmt(tol.rtol_post)],
        ["absolute tolerance added to both", fmt(tol.atol)],
    ];
    caption="How the port is judged (test/tolerances.toml)",
)

# The relative difference of two values `a` and `b` is their difference divided by the
# larger of the two magnitudes, after allowing the absolute tolerance.
#
# > ℹ️ **Why two regions (finding F-08).** In a valid step the model is well
# > conditioned: a last-bit difference stays a last-bit difference (below about 4e-9).
# > When a step fails, the legacy code writes `Inf` into CO₂ and O₂ but **keeps
# > integrating** from the invalid state. The steps after that are badly conditioned,
# > and the same last-bit differences grow, up to 9.0e-6 relative so far (golden
# > fixtures from the Fortran compiled in CI, November 2026). The limit after a
# > failure is 1e-4, about 11 times the largest difference seen. A real porting
# > error is still caught: it changes valid steps by far more than 1e-8, or moves a
# > failure, or changes a % outbound, and all three are checked separately.
#
# ### 2.2 Three levels of evidence
#
# The comparison can be made at three levels. They differ in what they need and in
# what they prove:

levels_table(env, RUN_LEVEL_B, RUN_LEVEL_C)

# ### 2.3 The test suite
#
# The package's tests are grouped (`test/runtests.jl`); CI runs them on Linux, macOS
# and Windows. Here each group runs with `Pkg.test()` in its own Julia process,
# exactly as on the command line (`GROUP=unit julia --project=. -e "using Pkg; Pkg.test()"`).
# Every process compiles the package once, so this takes several minutes.
#
# | group | what it checks |
# |:--|:--|
# | `unit` | physics pieces, step-status invariants on 200 prior draws, options, input validation, zero allocations, Float32 and ForwardDiff inputs |
# | `io` | the CSV reader, prior table, time arrays, proxies, temperature data |
# | `sampling` | Latin hypercube strata, truncated priors (KS tests), inverse-Wishart degrees of freedom, sampler moments |
# | `constraints` | CO₂ and temperature windows, % outbound |
# | `workflow` | configuration files, the engine (stopping rule, determinism across thread counts, checkpoints), saving, analysis |
# | `regression` | **level A**: the golden master against stored Fortran output |
# | `quality` | Aqua.jl: stale dependencies, compat bounds, type piracy, ambiguities |
# | `doctests` | the examples in the docstrings |

println("running ", length(TEST_GROUPS), " test groups:")
test_results = run_test_groups(TEST_GROUPS)
test_results_table(test_results)

#-

plot_test_results(test_results)

# Each group's full output is in the log file named in `test_results`; for example
# `test_results[1].log`.
#
# ### 2.4 Level A: the golden master
#
# `test/fixtures/fortran/` holds inputs and outputs of the **compiled original
# Fortran** for 100 prior samples, for the main model and the six supplemental
# variants (produced by the unmodified R/Fortran code, see
# `test/fixtures/README.md`). The `regression` group above checks them with
# pass/fail. Here the same comparison is repeated with the numbers kept, so you can
# see how close the agreement is, not only that it passes:

golden = golden_master_checks()
plot_headroom(golden; title="Level A: Julia against the stored output of the compiled Fortran")

# How to read the figure: each row is one quantity of one model variant. The dot is
# the largest relative difference over all its cells (runs × steps); the dashed line
# is the tolerance; the shaded zone is where the check would fail. Left: cells before
# a run's first failed step (limit 1e-8). Right: cells at or after it, where the
# legacy code integrates from an invalid state (finding F-08, section 2.1) and the
# limit is 1e-4. Rows labelled "pass/fail positions" are not drawn: they require the
# failed steps to be in identical places, and their result is in the table.

checks_table(golden; collapsed="All $(length(golden)) level-A checks (click to expand)")

# ### 2.5 Level B: replaying stored exports of the original code
#
# When the original R/Fortran code has been run on this machine before (level C, or
# `test/legacy_comparison/run_comparison.jl`), its inputs and outputs are in
# `test/legacy_comparison/output/`. That folder is not in git, so a fresh clone has
# none. If they exist, they are copied to a temporary folder and compared there, so
# the stored files are never overwritten.

resB = (RUN_LEVEL_B && env.exports.available) ? replay_stored_exports() : nothing
level_status(resB, :B, env, RUN_LEVEL_B)

#-

level_headroom(resB, "Level B: Julia against stored exports of the original R/Fortran code")

#-

level_checks_table(resB, "level-B")

# The figures below are drawn by the repository's own
# `test/legacy_comparison/plot_comparison.jl` from these results. The **centre run**:
# legacy and Julia trajectories at the prior means, and their relative difference at
# each age.

comparison_figure(resB, :fig_centre_run)

# **All samples**: quantile bands of CO₂ and temperature (legacy filled, Julia as
# lines), and the share of valid steps at each age. The two should be
# indistinguishable.

comparison_figure(resB, :fig_ensemble)

# **Every finite cell**, Julia against legacy, coloured by region:

comparison_figure(resB, :fig_one_to_one)

# **Distribution of the relative differences**, with both tolerances. Many cells are
# exactly equal (leftmost bar):

comparison_figure(resB, :fig_histograms)

# **Where the differences are**, per run and age. Failed steps are grey; the orange
# line marks each run's first failure. Larger differences sit to the right of it,
# which is finding F-08 made visible:

comparison_figure(resB, :fig_heatmaps)

# **Largest and median difference at each age**:

comparison_figure(resB, :fig_by_age)

# **% outbound**, which decides acceptance, must be identical for every run:

comparison_figure(resB, :fig_percent_outbound)

# **Single- against double-precision literals** (finding F-05, section 1.9), against
# the legacy output:

comparison_figure(resB, :fig_literals)

# ### 2.6 Level C: running the original code now
#
# Level C runs the unmodified R/Fortran code (`legacy/`) through
# `test/legacy_comparison/run_legacy.R` into a temporary folder: 1000 prior samples
# drawn by the original R sampling code, and the six supplemental variants on 200 of
# them. Julia is then fed **exactly those samples** (R and Julia use different random
# number generators) and compared. If the Fortran libraries are not compiled yet, R
# compiles them (`R CMD SHLIB`) into `legacy/fortran/`. The R step takes under a
# minute; the comparison about two.

run_c = RUN_LEVEL_C === true || (RUN_LEVEL_C === :auto && level_c_possible(env))
resC = run_c ? run_live_legacy(env) : nothing
level_status(resC, :C, env, RUN_LEVEL_C)

#-

level_headroom(resC, "Level C: Julia against the original R/Fortran code, run now")

#-

level_checks_table(resC, "level-C")

#-

comparison_figure(resC, :fig_heatmaps)

# ### 2.7 Verdict

verdict_table([
    ("A: golden master", "stored output of the compiled Fortran", summarize_checks(golden)),
    ("B: replay", "stored exports of the R/Fortran code", isnothing(resB) ? nothing : summarize_checks(resB.checks)),
    ("C: live", "the R/Fortran code, run now", isnothing(resC) ? nothing : summarize_checks(resC.checks)),
])

#-

overall_verdict(test_results, golden, resB, resC)

# ### 2.8 Reproducibility record
#
# Versions and paths, for the record. The full text reports of levels B and C
# (`comparison_report.txt`, with the worst cells of every region) are in the folders
# printed here.

environment_table(env)

#-

versioninfo()
println("\nGeocarbPrecalibration ", env.package, " at commit ", env.commit)
isnothing(resB) || println("level B report: ", resB.report)
isnothing(resC) || println("level C report: ", resC.report)
nothing

# ### References
#
# - Berner, R. A. (2004). *The Phanerozoic Carbon Cycle: CO2 and O2.* Oxford University Press.
# - Foster, G. L., Royer, D. L., & Lunt, D. J. (2017). Future climate forcing potentially without precedent in the last 420 million years. *Nature Communications* 8, 14845.
# - Mills, B. J. W., et al. (2019). Modelling the long-term carbon cycle, atmospheric CO2, and Earth surface temperature from late Neoproterozoic to present day. *Gondwana Research* 67, 172–186.
# - Park, J., & Royer, D. L. (2011). Geologic constraints on the glacial amplification of Phanerozoic climate sensitivity. *American Journal of Science* 311, 1–26.
# - Royer, D. L., et al. (2014). Error analysis of CO2 and O2 estimates from the long-term geochemical model GEOCARBSULF. *American Journal of Science* 314, 1259–1283.
# - Wong, T. E., Cui, Y., Royer, D. L., & Keller, K. (2021). A tighter constraint on Earth-system sensitivity from long-term temperature and carbon-cycle observations. *Nature Communications* 12, 3173.
