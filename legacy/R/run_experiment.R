##==============================================================================
## run_experiment.R
##
## Single entry point for ONE Latin hypercube precalibration experiment with the
## GEOCARB model (the same procedure as lhs.R, which `lhs_driver.R` repeats for
## 15 experiments). Edit the CONFIG block below, then run:
##
##    cd R
##    Rscript run_experiment.R          (or source("run_experiment.R") in R)
##
## Settings below: CO2 + temperature constraints, 50% outbound, seed 42.
##
## DATA FLOW (input -> output)
## ---------------------------
##  input_data/ (CONFIG: input files)
##    GEOCARB_input_summaries_calib_<param_choice>.csv  prior distributions of the
##    |                                                  calibration parameters
##    GEOCARB_input_arrays_NewDegassing.csv             time-varying parameter
##    |                                                  means/errors (fSR_choice)
##    CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv   CO2 proxy data
##    Mills_GR_2019_temp_co2.csv                        temperature data
##        |
##        v  model_setup.R / parameterSetup.R / getData.R / constraints.R
##    parameter priors + precalibration windows (CO2 and temperature, per time step)
##        |
##        v  lhs_sampling.R
##    Latin hypercube sample of the constant parameters; time series sampled from an
##    inverse-Wishart / multivariate normal around the input arrays
##        |
##        v  model_run.R -> run_geocarbF.R -> fortran/run_geocarb.f90
##    CO2, O2 and temperature time series for every sample
##        |
##        v  percent_outbound.R
##    keep samples with percent-outbound <= threshold (for the data sets selected);
##    stop once `n_sample_min` samples are kept
##        |
##        v
##  output/ (CONFIG: output_dir), tag = "<c|t|ct>_out<threshold %>", here "ct_out50"
##    lhs_param_<tag>.RData   par_calib_save (n_saved x n_params constant parameters),
##    |                       par_time_save  (n_time x n_saved x n_time_params)
##    lhs_covar_<tag>.RData   par_covar_save (time-series covariance matrices)
##    lhs_model_<tag>.RData   run_geocarb output for the saved samples:
##    |                       time, co2_save, temp_save, o2_save (n_time x n_saved),
##    |                       prcout_co2_save, prcout_temp_save, n_simulated
##    run_info_<tag>.txt/.RData  the settings used, counts, versions, timestamp
##
## PREREQUISITES
##  * R packages: run `source("install_packages.R")` once.
##  * Compiled Fortran model in ../fortran (see ../README.md). On Windows
##    run_geocarbF.R loads ../fortran/run_geocarb.dll, e.g. from the fortran folder:
##      gfortran -shared -fno-range-check -o run_geocarb.dll src/run_geocarb.f90
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

rm(list=ls())

##==============================================================================
## CONFIG -- everything you normally need to change is in this block
##==============================================================================

## --- Experiment ---------------------------------------------------------------
use_co2 <- TRUE               # require simulations to match the CO2 windows?
use_temperature <- TRUE       # require simulations to match the temperature windows?
prcout_threshold_pct <- 30    # keep simulations with at most this % of time steps
                              # outside the windows (percent, 0-100)
seed <- 42                    # random number seed (same seed -> same results)

## --- Sampling -----------------------------------------------------------------
n_sample <- 20000000          # maximum number of simulations to run
n_sample_per_chunk <- 10000   # simulations (and covariance arrays) held in RAM at once
n_sample_min <- 10000         # stop after this many simulations pass (avoids overrunning RAM)
                              # set > n_sample to run all n_sample simulations
n_node <- 1                   # (unused placeholder from the original code)

## --- Model choices ------------------------------------------------------------
param_choice <- 'all'         # calibrate all 68 parameters ("all") or the 6 of PR2011 ("PR2011")
data_choice <- 'F2017'        # CO2 data set: "F2017" (Foster et al 2017) or "PR2011"
fSR_choice <- 'DT2019'        # fSR time series: "PR2011", "LENTON" or "DT2019"

## --- Input files (paths relative to this R/ directory) ------------------------
# CO2 proxy data (age, co2, co2_high, ...); windows are built from these
filename.data <- '../input_data/CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv'
# Temperature data (time, CO2 and T max/min/avg) from Mills et al (2019); used for temperature windows
filename.temperature <- '../input_data/Mills_GR_2019_temp_co2.csv'
# Parameter prior distributions are read from
#   ../input_data/GEOCARB_input_summaries_calib_<param_choice>.csv   (model_setup.R)
# and time-varying parameter arrays from
#   ../input_data/GEOCARB_input_arrays_NewDegassing.csv   (fSR_choice = "DT2019"; see parameterSetup.R)

## --- Output -------------------------------------------------------------------
output_dir <- '../output/'    # must end in "/"
plot.dir <- '../figures/'     # needed by some sourced scripts

##==============================================================================
## END CONFIG
##==============================================================================


## Work from the directory containing this script, so the relative paths work
script_dir <- NULL
file_arg <- grep("^--file=", commandArgs(trailingOnly=FALSE), value=TRUE)
if (length(file_arg) > 0) {
  script_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[1])))
} else if (!is.null(sys.frame(1)$ofile)) {  # source("run_experiment.R")
  script_dir <- dirname(normalizePath(sys.frame(1)$ofile))
}
if (!is.null(script_dir)) {setwd(script_dir)}
if (!file.exists("lhs.R")) {stop("Run from the R/ directory (could not find lhs.R in ", getwd(), ")")}
if (!dir.exists(output_dir)) {dir.create(output_dir, recursive=TRUE)}

library(foreach)
library(doParallel)
library(lhs)
library(Hmisc)
library(CholWishart)
library(abind)
library(MASS)

# lhs.R and its sourced scripts expect the threshold as a fraction
prcout_threshold <- prcout_threshold_pct/100
config_names <- c("use_co2", "use_temperature", "prcout_threshold_pct", "prcout_threshold",
                  "seed", "n_sample", "n_sample_per_chunk", "n_sample_min", "param_choice",
                  "data_choice", "fSR_choice", "filename.data", "filename.temperature",
                  "output_dir")
config <- mget(config_names)

## Run the experiment (samples, runs run_geocarb, filters, and saves the outputs)
set.seed(seed)
source("lhs.R")

## Record what was run
run_info <- c(config,
              list(n_simulated = n_simulated,
                   n_saved = nrow(par_calib_save),
                   finished = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                   R_version = R.version.string))
tag <- paste0(data_appen, "_out", prcout_threshold*100)
save(run_info, file=paste0(output_dir, "run_info_", tag, ".RData"))
writeLines(paste0(names(run_info), " = ", sapply(run_info, paste, collapse=", ")),
           paste0(output_dir, "run_info_", tag, ".txt"))

print(paste0("Saved ", nrow(par_calib_save), " of ", n_simulated, " simulations to ", output_dir))

##==============================================================================
## End
##==============================================================================
