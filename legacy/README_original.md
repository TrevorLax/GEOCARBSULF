# README:  GEOCARB-precalibration

## Purpose

To improve estimates of Earth-system sensitivity by assimilating deep-time paleoclimate CO2 proxy data with the GEOCARBSULFvolc long-term carbon cycle model. This is done using a windowing precalibration approach, via Latin hypercube sampling.

## Installation and compilation

In a parameter-space with the 60+ dimensions that GEOCARB has, Monte Carlo sampling requires a great many model executions. To speed things up, the model is written in Fortran and called from R. After pulling the codes, you will need to navigate to the `fortran` directory and compile the core Fortran model:
* In a terminal window, navigate to the `fortran` directory (`cd fortran`)
* If the `obj` subdirectory is not present, then create it (`mkdir obj`)
* Make sure the file named `Makefile` has the proper directory path to your Fortran-90 compiler (line 5). Two common ones are given, with one commented out (line 6).
* Run the Makefile to compile the model (in the terminal window, enter the command: `make`).
* If you get an error complaining about `missing xcrun at...`, try running in the terminal: `xcode-select --install`.

## Running a single experiment

To run one precalibration experiment (rather than the full set in `lhs_driver.R`), edit the CONFIG block at the top of `R/run_experiment.R` (data sets, % outbound threshold, seed, sample sizes, input files, output directory) and run `Rscript run_experiment.R` from the `R` directory. The script header documents the path from input data to output files. On Windows, first compile the model to a DLL: `gfortran -shared -fno-range-check -o run_geocarb.dll src/run_geocarb.f90` (from `fortran`).

## Workflow

After compiling the model (above), what follows assumes you start in the `R` directory of the code repository. The general workflow to reproduce the results of the manuscript Wong et al., **A tighter constraint on Earth-system sensitivity from long-term temperature and carbon-cycle observations**, is as follows.

1. Install the relevant packages by running `source("install_packages.R")`
1. Run the main text Latin hypercube precalibration experiments by running `source("lhs_driver.R")`. This will take a long time!
  1. Between lines 42 and 53, you will notice that there are machine- and user-dependent file paths being set. If you are not me, you will likely need to change these. They are so that you can, in principle, run this code from the command line on a remote cluster.
  1. In that file, the settings used for the Wong et al. paper are:
  ```
  n_sample <- 20000000
  n_sample_per_chunk <- 10000
  n_sample_min <- 10000
  param_choice <- 'all'
  data_choice <- 'F2017'
  fSR_choice <- 'DT2019'
  threshold_choices <- c(.3, .35, .4, .45, .5)
  ```
  1. The 30% outbound experiment (`threshold_choices=0.3`) with both CO2 and temperature data takes the longest to run (because you're using both constraints and requiring simulations to match the precalibration windows for both in at least 70% of the time-steps). Even with `n_sample=20,000,000`, fewer than 10,000 simulations satisfy the precalibration constraints within 30% outbound. So you will notice that this experiment is run two more times with different random number seeds in order to obtain an ensemble of similar size to the other experiments.
1. Next there are two supplemental Latin hypercube experiments to run.
  1. `source("lhs_driver_supp.R")` will run the linear change in $\Delta T_{2x}$ experiment (along with a few others that are not presented in the manuscript but you're invited to check out). These supplemental experiments only use a %outbound threshold of 50%, for time's sake.
  1. `source("lhs_driver_cret.R")` will run the Cretaceous temperature-matching experiment where simulations are forced to agree with the temperature windows in a time-step during the Cretaceous period (around 100 Myr ago).
    1. Note that for the Cretaceous temperature-matching experiments, the first time through `lhs_driver_cret.R`, `use_cret_means` should be `FALSE`.
    1. Then, while doing the analysis of that initial Cretaceous experiment in `cretaceous_experiment.R` (below), the file `par_time_mean_cret.csv` will be written.
    1. At that point, you can go back and re-run `lhs_driver_cret.R` with `use_cret_means=TRUE`. This experiment will update the centers of the time series parameters to the a posteriori results from the initial Cretaceous-matching experiment.
1. Next, run `source("analysis_and_plots.R")` to analyze the model output from these experiments. This will create figures, output CSV files and print results to the screen.
  1. Within `analysis_and_plots.R`, the script `analysis_supplemental_experiments.R` will be run. This will analyze *all* of the supplemental experiments that are detailed in `lhs_driver_supp.R` including some modifying the gymnosperm/angiosperm domination timing, which is not presented in the Wong et al. study.
  1. Additional analysis of the Cretaceous temperature-matching experiment is conducted in `cretaceous_experiment.R`.

## Redistribution and use

Please redistribute, please modify and please use! This code is part of GEOCARB-precalibration.
GEOCARB-precalibration is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

GEOCARB-precalibration is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with GEOCARB-precalibration.  If not, see <http://www.gnu.org/licenses/>.

## Questions?

There will always be questions. Whether you are trying to get the model to run, or wondering what a line of code does, we would love to talk to you. Do not hesitate to reach out to us at:
* Tony Wong (aewsma at rit.edu)
* Ying Cui (cuiy at montclair.edu)
