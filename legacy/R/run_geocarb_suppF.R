##==============================================================================
## run_geocarb_suppF.R
##
## R wrapper script to call the fortran version of the geocarbsulf model.
## The most important thing this does is unravel the various inputs into the
## order that the fortran model expects.
##
## version for supplemental experiments
##
## Input:
##  Matrix_56    vector of the 56 constant parameters to calibrate
##  Matrix_12    ageN x 12 matrix of the time-varying parameters to calibrate
##  age          ageN x 1 vector of the years (Millino years ago) of the simulation
##  ageN         how many time steps?
##  iteration_threshold   how many times to iterate the convergence function within run_geocarb?
##  ind_expected_time     how to reorder Matrix_12 to what run_geocarb.f90 expects
##  ind_expected_const    how to reorder Matrix_56 to what run_geocarb.f90 expects
##
## Output:
##  f.output$CO2
##  f.output$O2
##  f.output$temp
##
## Created originally 7 August 2017 by Tony Wong.
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

# load fortran subroutine (# to check if library is loaded is.loaded("run_geocarb") )
if(.Platform$OS.type == "unix") {
    dyn.load("../fortran/run_geocarb_supp.so")
} else {
    dyn.load("../fortran/run_geocarb_supp")
}

run_geocarb_suppF <- function(Matrix_56,
                         Matrix_12,
                         supp_experiment_parameters=c(130,80,1,1),
                         age,
                         ageN,
                         iteration_threshold,
                         ind_expected_time,
                         ind_expected_const
) {

  # reorganzie Matrix_56 (56x1 vector) and Matrix_12 (ageNx12 time series) into
  # the orders that run_geocarb.f90 expects
  Matrix_12_ordered <- as.matrix(Matrix_12[,ind_expected_time])
  Matrix_56_ordered <- Matrix_56[ind_expected_const,]

  # fortran version
  f.output <- .Fortran('run_geocarb_supp',
                       Matrix_56 = as.double(Matrix_56_ordered),
                       Matrix_12 = as.double(Matrix_12_ordered),
                       age_gym_ang_beg = supp_experiment_parameters[1],
                       age_gym_ang_end = supp_experiment_parameters[2],
                       gym_fac   = supp_experiment_parameters[3],
                       dT2X_fac  = supp_experiment_parameters[4],
                       age       = as.double(age),
                       ageN      = as.integer(ageN),
                       iteration_threshold = as.integer(iteration_threshold),
                       CO2_out   = as.double(rep(-999.99, ageN)),
                       O2_out    = as.double(rep(-999.99, ageN)),
                       temp_out  = as.double(rep(-999.99, ageN))
                       )
  # r version
  ###f.output <- GEOCARBSULFvolc_forMCMC(Matrix_56_ordered, Matrix_12_ordered, age, ageN)

  return(f.output)
}


##==============================================================================
## End
##==============================================================================
