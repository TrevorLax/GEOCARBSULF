##==============================================================================
## lhs_driver_cret.R
##
## Runs the supplemental experiment for Cretaceous constraint.
## --> only permit simulations that match temperature window at ~100 Mya
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

## Clear workspace
rm(list=ls())

# needed packages
library(lhs)
library(Hmisc)
library(CholWishart)
library(abind)
library(MASS)

if(Sys.info()['user']=='tony') {
  # Tony's local machine (if you aren't me, you almost certainly need to change this...)
  machine <- 'local'
  setwd('/Users/tony/codes/GEOCARB-precalibration/R')
} else if(Sys.info()['user']=='aewsma') {
  machine <- 'office'
  setwd('/Users/aewsma/codes/GEOCARB-precalibration/R')
} else {
  # assume on another cluster of some kind...
  machine <- 'remote'
  setwd('~/work/codes/GEOCARB-precalibration/R')
}

## Set testing number of samples and file name appendix here
## if there aren't enough samples on the MCMC output file, will break.
n_sample <- 10000000
n_sample_per_chunk <- 10000 # maximum number of time series samples to consider at once
n_sample_min <- 10000 # minimum number of samples we'd be happy with; stop after this to avoid overrunning RAM
# if you don't want to use this, just set it greater than n_sample
n_node <- 1 # distribute the chunks across multiple nodes?

param_choice <- 'all'   # Calibrate all 68 parameters? ("all") or only the 6 from Park and Royer 2011 ("PR2011")
data_choice <- 'F2017'  # Which data set?  PR2011 = Park and Royer (2011), or F2017 = Foster et al (2017)
fSR_choice <- 'DT2019'  # Which fSR time series? ("PR2011", "LENTON", "DT2019")
plot.dir <- '../figures/'
use_cret_means <- FALSE # use the means from the Cretaceous-matching experiment?
#                   ^-- Should be FALSE the first time you run this, then TRUE if you want to use updated time series parameter means

threshold_choices <- c(.3)
experiments <- expand.grid(threshold = threshold_choices,
                           use_co2 = c(FALSE, TRUE),
                           use_temperature = c(FALSE, TRUE))
# remove the experiments with both use_co2 = use_temperatures = FALSE
experiments <- experiments[-which(experiments$use_co2==FALSE & experiments$use_temperature==FALSE),]

# only doing the CO2+temperature experiment
for (idx_experiment in c(3)) {

  set.seed(1234*idx_experiment) # for reproducibility, but also for different samples for each experiment
  prcout_threshold <- experiments[idx_experiment,"threshold"]  # only save simulations with percent_outbound < this
  use_temperature <- experiments[idx_experiment,"use_temperature"]
  use_co2 <- experiments[idx_experiment,"use_co2"]

  # supplemental experiment modifying both GYM and timing
  appen <- "cret"#; supp_experiment_parameters <- c(110,60,0.25,-1)
  source("lhs_cret.R")
  #Sys.sleep(180) # cool down for a few minutes

}


##==============================================================================
## End
##==============================================================================
