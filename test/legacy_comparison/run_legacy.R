#!/usr/bin/env Rscript
##==============================================================================
## run_legacy.R
##
## Run the ORIGINAL R/Fortran precalibration code (unmodified, from the legacy
## directory) on a small sample and export everything needed to check the Julia
## port: inputs, intermediate values and model outputs, written as CSV with 17
## significant digits so that no precision is lost.
##
## Usage (normally called by run_comparison.jl):
##   Rscript run_legacy.R <legacy_root> <out_dir> [n_sample=1000] [n_supp=200] [seed=2026]
##
## <legacy_root> must contain the original R/, fortran/ and input_data/ folders.
## The compiled Fortran libraries are built with `R CMD SHLIB` if they are missing.
##
## What is run:
##   * lhs.R with use_co2 = use_temperature = TRUE and prcout_threshold = 1, so that
##     every simulation with a defined %outbound is kept (n_sample in two chunks);
##   * model_run_supp() for the first n_supp kept samples under the six
##     supplemental-experiment settings of lhs_driver_supp.R / analysis_supplemental_experiments.R;
##   * one model_run() at the prior means and time-array centres.
##
## Nothing in the legacy code is changed. The only addition is a shim
## `ceil <- ceiling` if `ceil` does not exist, because time_series_df.R calls
## ceil(), which is not base R (finding F-13).
##==============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("usage: Rscript run_legacy.R <legacy_root> <out_dir> [n_sample] [n_supp] [seed]")
}
legacy_root <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
out_dir <- args[2]
n_sample_arg <- if (length(args) >= 3) as.integer(args[3]) else 1000L
n_supp_arg <- if (length(args) >= 4) as.integer(args[4]) else 200L
seed_arg <- if (length(args) >= 5) as.integer(args[5]) else 2026L
if (n_sample_arg < 4) stop("n_sample must be at least 4")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_dir <- normalizePath(out_dir, winslash = "/", mustWork = TRUE)
t_start <- proc.time()

## ---- R packages ----------------------------------------------------------------
needed <- c("lhs", "CholWishart", "abind", "MASS")
have <- vapply(needed, requireNamespace, logical(1), quietly = TRUE)
if (!all(have)) {
  lib <- Sys.getenv("R_LIBS_USER")
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(lib, .libPaths()))
  message("Installing missing R packages into ", lib, ": ", paste(needed[!have], collapse = ", "))
  install.packages(needed[!have], lib = lib, repos = "https://cloud.r-project.org")
}
suppressPackageStartupMessages({
  library(lhs); library(CholWishart); library(abind); library(MASS)
})

## ---- compiled Fortran ----------------------------------------------------------
fortran_dir <- file.path(legacy_root, "fortran")
build_lib <- function(name) {
  lib <- file.path(fortran_dir, paste0(name, .Platform$dynlib.ext))
  if (file.exists(lib)) return(invisible(lib))
  src <- file.path(fortran_dir, "src", paste0(name, ".f90"))
  message("Compiling ", src, " -> ", lib, " with R CMD SHLIB")
  old <- setwd(file.path(fortran_dir, "src"))
  on.exit(setwd(old), add = TRUE)
  Sys.setenv(PKG_FFLAGS = "-fno-range-check", PKG_FCFLAGS = "-fno-range-check")
  q <- function(x) shQuote(x, type = if (.Platform$OS.type == "windows") "cmd" else "sh")
  status <- system2(file.path(R.home("bin"), "R"),
                    c("CMD", "SHLIB", "-o", q(lib), q(basename(src))))
  if (status != 0 || !file.exists(lib)) {
    stop("Could not compile ", src, ". Compile it by hand, for example:\n  gfortran -shared -fPIC -fno-range-check -o ",
         lib, " ", src)
  }
  invisible(lib)
}
build_lib("run_geocarb")
build_lib("run_geocarb_supp")

## ---- run the original precalibration code --------------------------------------
setwd(file.path(legacy_root, "R"))
shims <- character(0)
if (!exists("ceil")) {
  ceil <- ceiling
  shims <- c(shims, "ceil <- ceiling (time_series_df.R calls ceil(), which is not base R)")
}

use_co2 <- TRUE
use_temperature <- TRUE
prcout_threshold <- 1.0          # keep every simulation whose %outbound is defined
n_sample <- n_sample_arg
n_sample_per_chunk <- ceiling(n_sample / 2)   # lhs_sampling.R needs more than one chunk (F-12)
n_sample_min <- n_sample
n_node <- 1
param_choice <- "all"
data_choice <- "F2017"
fSR_choice <- "DT2019"
output_dir <- paste0(file.path(out_dir, "rdata"), "/")
dir.create(output_dir, showWarnings = FALSE)
plot.dir <- paste0(out_dir, "/")

set.seed(seed_arg)
source("lhs.R")

## ---- export ----------------------------------------------------------------------
fmt <- function(x) {
  s <- sprintf("%.17g", x)
  s[is.na(x)] <- "NA"
  s[is.nan(x)] <- "NaN"
  s[!is.na(x) & x == Inf] <- "Inf"
  s[!is.na(x) & x == -Inf] <- "-Inf"
  s
}
write_mat <- function(m, file, header) {
  m <- as.matrix(m)
  storage.mode(m) <- "double"
  stopifnot(ncol(m) == length(header))
  lines <- apply(m, 1, function(r) paste(fmt(r), collapse = ","))
  writeLines(c(paste(header, collapse = ","), lines), file.path(out_dir, file))
}

const_names <- colnames(par_calib_save)
time_names <- colnames(par_time_center)
n_saved <- nrow(par_calib_save)
n_t <- length(time)

write_mat(par_calib_save, "constants.csv", const_names)
ts <- matrix(NA_real_, n_saved, n_t * length(time_names))
for (pp in seq_along(time_names)) {
  ts[, ((pp - 1) * n_t + 1):(pp * n_t)] <- t(par_time_save[, , pp])
}
write_mat(ts, "time_series.csv", paste(rep(time_names, each = n_t), rep(1:n_t, times = length(time_names)), sep = "_"))
step_names <- paste0("step_", 1:n_t)
write_mat(t(co2_save), "legacy_co2.csv", step_names)
write_mat(t(o2_save), "legacy_o2.csv", step_names)
write_mat(t(temp_save), "legacy_temp_plus15.csv", step_names)
write_mat(cbind(prcout_co2_save, prcout_temp_save), "legacy_prcout.csv", c("co2", "temp"))
write_mat(cbind(as.vector(age), windows$co2[, "low"], windows$co2[, "high"], windows$temp[, "low"], windows$temp[, "high"]),
          "legacy_windows.csv", c("age", "co2_low", "co2_high", "temp_low", "temp_high"))
write_mat(as.matrix(par_time_center), "legacy_time_center.csv", time_names)
write_mat(as.matrix(par_time_stdev), "legacy_time_sigma.csv", time_names)
write_mat(matrix(as.vector(df), nrow = 1), "legacy_dof.csv", rownames(df))
write_mat(parameters_lhs, "legacy_lhs_cdf.csv", const_names)
write_mat(do.call(rbind, par_calib), "legacy_lhs_values.csv", const_names)

## one run at the prior means and the time-array centres
center_run <- model_run(par_calib = par_calib0, par_time = par_time_center, par_fixed = par_fixed0,
                        parnames_calib = parnames_const_calib, parnames_fixed = parnames_const_fixed,
                        parnames_time = parnames_time_calib, age = age, ageN = ageN,
                        ind_const_calib = ind_const_calib, ind_time_calib = ind_time_calib,
                        ind_const_fixed = ind_const_fixed, ind_time_fixed = ind_time_fixed,
                        ind_expected_time = ind_expected_time, ind_expected_const = ind_expected_const,
                        iteration_threshold = iteration_threshold)
write_mat(center_run, "legacy_center_run.csv", c("age", "co2", "o2", "temp"))

## supplemental-experiment variants (analysis_supplemental_experiments.R:179-186)
source("run_geocarb_suppF.R")
source("model_run_supp.R")
supp <- list(control = c(130, 80, 1, -1), gym = c(130, 80, 0.25, -1), timing = c(110, 60, 1, -1),
             gym_timing = c(110, 60, 0.25, -1), dT2X = c(130, 80, 1, 1), gym_timing_dT2X = c(110, 60, 0.25, 1))
n_supp <- min(n_supp_arg, n_saved)
cfg <- do.call(rbind, supp)
write_mat(cfg, "legacy_supp_configs.csv", c("age_gym_ang_beg", "age_gym_ang_end", "gym_fac", "dT2X_fac"))
writeLines(names(supp), file.path(out_dir, "legacy_supp_names.txt"))
for (nm in names(supp)) {
  co2m <- o2m <- tempm <- matrix(NA_real_, n_supp, n_t)
  for (ii in 1:n_supp) {
    mo <- model_run_supp(par_calib = par_calib_save[ii, ], par_time = par_time_save[, ii, ],
                         par_fixed = par_const_fixed0, parnames_calib = parnames_const_calib,
                         parnames_fixed = parnames_const_fixed, parnames_time = parnames_time_calib,
                         age = age, ageN = ageN, ind_const_calib = ind_const_calib,
                         ind_time_calib = ind_time_calib, ind_const_fixed = ind_const_fixed,
                         ind_time_fixed = ind_time_fixed, ind_expected_time = ind_expected_time,
                         ind_expected_const = ind_expected_const,
                         iteration_threshold = iteration_threshold,
                         supp_experiment_parameters = supp[[nm]])
    co2m[ii, ] <- mo[, "co2"]; o2m[ii, ] <- mo[, "o2"]; tempm[ii, ] <- mo[, "temp"]
  }
  write_mat(co2m, paste0("legacy_supp_", nm, "_co2.csv"), step_names)
  write_mat(o2m, paste0("legacy_supp_", nm, "_o2.csv"), step_names)
  write_mat(tempm, paste0("legacy_supp_", nm, "_temp.csv"), step_names)
}

elapsed <- (proc.time() - t_start)[["elapsed"]]
writeLines(c(paste("R:", R.version.string),
             paste("legacy_root:", legacy_root),
             paste("seed:", seed_arg),
             paste("n_sample:", n_sample),
             paste("n_saved:", n_saved),
             paste("n_supp:", n_supp),
             paste("iteration_threshold:", iteration_threshold),
             paste("main library:", file.path(fortran_dir, paste0("run_geocarb", .Platform$dynlib.ext))),
             paste("shims:", if (length(shims)) paste(shims, collapse = "; ") else "none"),
             paste("elapsed_seconds:", round(elapsed, 1))),
           file.path(out_dir, "legacy_meta.txt"))
cat("Legacy R/Fortran run finished:", n_saved, "samples kept of", n_sample, "in", round(elapsed, 1), "s\n")
