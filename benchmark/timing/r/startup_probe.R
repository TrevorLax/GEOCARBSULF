## startup_probe.R: in-process part of the cold-start measurements (plan §3.1).
##   S1  library() of the packages lhs.R needs, in process
##   S2  the legacy set-up (model_setup.R, which also dyn.loads the Fortran, and constraints.R)
##   S3  first model_run() after the set-up, then a warm call (model_setup.R itself already
##       ran the model once, so in R "first call" is not a compilation step)
t0 <- proc.time()[["elapsed"]]
.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(.this_dir, "..", "lib", "common.R"))
job <- read_job(commandArgs(trailingOnly = TRUE)[1])
w <- raw_writer(job)
m <- measure(function() suppressPackageStartupMessages({ library(lhs); library(CholWishart); library(MASS); library(abind); library(Hmisc) }))
record(w, "R0", "S1", m$wall, subcomponent = "library(lhs, CholWishart, MASS, abind, Hmisc) (in process)", mode = "cold")
s <- legacy_setup(jstr(job, "legacy_dir"))
record(w, "R0", "S2", s, subcomponent = "input set-up", mode = "first_call")
run1 <- function() model_run(par_calib = par_calib0, par_time = par_time_center, par_fixed = par_fixed0,
  parnames_calib = parnames_const_calib, parnames_fixed = parnames_const_fixed, parnames_time = parnames_time_calib,
  age = age, ageN = ageN, ind_const_calib = ind_const_calib, ind_time_calib = ind_time_calib,
  ind_const_fixed = ind_const_fixed, ind_time_fixed = ind_time_fixed, ind_expected_time = ind_expected_time,
  ind_expected_const = ind_expected_const, iteration_threshold = iteration_threshold)
m <- measure(run1)
check(all(is.finite(m$value[, "co2"])), "prior-mean run failed")
record(w, "R0", "S3", m$wall, subcomponent = "first model_run after set-up", mode = "first_call")
m <- measure(run1)
record(w, "R0", "S3", m$wall, subcomponent = "model_run", mode = "warm")
## repeated set-up last: re-sourcing redefines model_run(), which R then byte-compiles again
s <- legacy_setup(jstr(job, "legacy_dir"))
record(w, "R0", "S2", s, subcomponent = "input set-up", mode = "warm")
