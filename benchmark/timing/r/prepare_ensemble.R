## prepare_ensemble.R: convert the shared ensemble written by julia/prepare_ensemble.jl into
## the objects lhs.R saves (par_calib_save with the calibrated constants in the order of
## parnames_const_calib, par_time_save as n_time x n x 12 in par_time_center order, and the
## model outputs), so that analysis_and_plots.R can load it.
##   Rscript prepare_ensemble.R <ensemble_dir> <legacy_root>
.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(.this_dir, "..", "lib", "common.R"))
a <- commandArgs(trailingOnly = TRUE)
dir <- normalizePath(a[1], winslash = "/"); legacy_root <- a[2]
load_legacy_packages()
legacy_setup(legacy_root)
cn <- strsplit(readLines(file.path(dir, "constant_names.txt")), ",")[[1]]
fn <- strsplit(readLines(file.path(dir, "forcing_names.txt")), ",")[[1]]
rd <- function(f, d) { x <- readBin(file.path(dir, f), "double", n = prod(d), size = 8, endian = "little"); dim(x) <- d; x }
n <- as.integer(file.size(file.path(dir, "constants.f64")) / 8 / length(cn))
C <- rd("constants.f64", c(n, length(cn))); colnames(C) <- cn
check(all(parnames_const_calib %in% cn), "ensemble lacks calibrated constants")
par_calib_save <- C[, parnames_const_calib, drop = FALSE]
TS <- rd("time_series.f64", c(n_time, n, length(fn)))
check(all(colnames(par_time_center) %in% fn), "ensemble lacks forcings")
par_time_save <- TS[, , match(colnames(par_time_center), fn), drop = FALSE]
co2_save <- rd("co2.f64", c(n_time, n)); o2_save <- rd("o2.f64", c(n_time, n)); temp_save <- rd("temp.f64", c(n_time, n)) + 15
P <- rd("prcout.f64", c(n, 2)); prcout_co2_save <- P[, 1]; prcout_temp_save <- P[, 2]; n_simulated <- n
save(list = c("par_calib_save", "par_time_save"), file = file.path(dir, "lhs_param_ensemble.RData"))
save(list = c("time", "co2_save", "temp_save", "o2_save", "prcout_co2_save", "prcout_temp_save", "n_simulated"),
     file = file.path(dir, "lhs_model_ensemble.RData"))
cat("wrote", file.path(dir, "lhs_param_ensemble.RData"), "\n")
