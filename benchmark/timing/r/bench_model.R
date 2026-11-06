## bench_model.R: R side of the model components (plan §3.2)
##   M2  wrapper layers on the 1000 legacy samples + prior-mean run:
##       (a) bare .Fortran on prepared arguments, (b) run_geocarbF(), (c) model_run()
##   M3  model_run_supp() for the 6 supplemental configurations
##   M4  per-sample times of model_run() (per-sample file)
## Every output is checked against the exports of test/legacy_comparison (exact for the
## library R used to make them, within the parity tolerances for rebuilt variants).

.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(.this_dir, "..", "lib", "common.R"))
job <- read_job(commandArgs(trailingOnly = TRUE)[1])
w <- raw_writer(job)
variant <- jstr(job, "variant")                  # R0 or R1_<fortran variant>
legacy_root <- jstr(job, "legacy_dir")
exports <- jstr(job, "exports_dir")
exact <- jbool(job, "exact", TRUE)
n_inputs <- jint(job, "model_inputs", 1001L)
n_supp <- jint(job, "supp_inputs", 200L)

suppressPackageStartupMessages({ library(lhs); library(CholWishart); library(abind); library(MASS) })
setup_s <- legacy_setup(legacy_root)
source("run_geocarb_suppF.R"); source("model_run_supp.R")

S <- legacy_samples_r(exports)
co2_ref <- read_export(exports, "legacy_co2.csv")
o2_ref <- read_export(exports, "legacy_o2.csv")
temp_ref <- read_export(exports, "legacy_temp_plus15.csv")
center_ref <- read_export(exports, "legacy_center_run.csv")
grp <- sample_groups_r(co2_ref)
check(identical(dimnames(S$series)[[3]], colnames(par_time_center)), "time_series.csv forcings are not in par_time_center order")
n_main <- min(nrow(S$constants), n_inputs - 1L)

## inputs of one call: sample 0 is the prior-mean run
par_calib_of <- function(i) if (i == 0) par_calib0 else S$constants[i, ]
par_time_of <- function(i) if (i == 0) par_time_center else { m <- S$series[i, , ]; colnames(m) <- colnames(par_time_center); m }

## Arguments as run_geocarbF passes them to .Fortran (model_run.R + run_geocarbF.R).
prepare_args <- function(i) {
  pc <- par_calib_of(i)
  M56u <- matrix(c(pc[ind_const_calib], par_const_fixed0[ind_const_fixed]), ncol = 1)
  rownames(M56u) <- c(parnames_const_calib[ind_const_calib], parnames_const_fixed[ind_const_fixed])
  list(m56 = as.double(M56u[ind_expected_const, ]), m12 = as.double(as.matrix(par_time_of(i)[, ind_expected_time])))
}

bare <- function(a) .Fortran("run_geocarb", Matrix_56 = a$m56, Matrix_12 = a$m12, age = as.double(age),
                             ageN = as.integer(ageN), iteration_threshold = as.integer(iteration_threshold),
                             CO2_out = as.double(rep(-999.99, ageN)), O2_out = as.double(rep(-999.99, ageN)),
                             temp_out = as.double(rep(-999.99, ageN)))
via_F <- function(i) {
  pc <- par_calib_of(i)
  M56u <- matrix(c(pc[ind_const_calib], par_const_fixed0[ind_const_fixed]), nrow = length(c(ind_const_calib, ind_const_fixed)), ncol = 1)
  rownames(M56u) <- c(parnames_const_calib[ind_const_calib], parnames_const_fixed[ind_const_fixed])
  run_geocarbF(Matrix_56 = M56u, Matrix_12 = par_time_of(i), age = age, ageN = ageN,
               iteration_threshold = iteration_threshold, ind_expected_time = ind_expected_time,
               ind_expected_const = ind_expected_const)
}
via_model_run <- function(i) {
  model_run(par_calib = par_calib_of(i), par_time = par_time_of(i), par_fixed = par_const_fixed0,
            parnames_calib = parnames_const_calib, parnames_fixed = parnames_const_fixed,
            parnames_time = parnames_time_calib, age = age, ageN = ageN, ind_const_calib = ind_const_calib,
            ind_time_calib = ind_time_calib, ind_const_fixed = ind_const_fixed, ind_time_fixed = ind_time_fixed,
            ind_expected_time = ind_expected_time, ind_expected_const = ind_expected_const,
            iteration_threshold = iteration_threshold)
}

idx <- c(0L, seq_len(n_main))
args_all <- lapply(idx, prepare_args)
co2_of <- function(layer, r) switch(layer, bare = r$CO2_out, run_geocarbF = r$CO2_out, model_run = r[, "co2"])

layers <- list(bare = function(k) bare(args_all[[k]]), run_geocarbF = function(k) via_F(idx[k]),
               model_run = function(k) via_model_run(idx[k]))

## warm-up (discarded): one pass of each layer over 50 samples
for (L in layers) for (k in seq_len(min(50, length(idx)))) L(k)

for (layer in names(layers)) {
  component(w, variant, "M2", workload = paste0("legacy_", length(idx)), function() {
    f <- layers[[layer]]
    co2 <- matrix(NA_real_, length(idx), ageN)
    per <- numeric(length(idx))
    c0 <- cpu_now(); t0 <- now()
    for (k in seq_along(idx)) {
      s <- now()
      r <- f(k)
      per[k] <- now() - s
      co2[k, ] <- co2_of(layer, r)
    }
    wall <- now() - t0; cpu <- cpu_now() - c0
    ## guards: the main samples against legacy_co2.csv, the prior-mean run against legacy_center_run.csv
    check_outputs(paste("R", layer, "co2"), co2[-1, , drop = FALSE], co2_ref[seq_len(n_main), , drop = FALSE], exact = exact)
    check_outputs(paste("R", layer, "centre"), co2[1, , drop = FALSE], t(center_ref[, "co2", drop = FALSE]), exact = exact)
    record(w, variant, "M2", wall / length(idx), subcomponent = layer, workload = paste0("legacy_", length(idx)),
           n = length(idx), cpu_s = cpu / length(idx), notes = "seconds per call")
    if (layer == "model_run") {
      for (k in seq_along(idx)) {
        i <- idx[k]
        record_per_sample(w, variant, "M4", i, if (i == 0) "prior_mean" else grp$group[i], NA,
                          if (i == 0) 0 else grp$n_failed[i], per[k])
      }
    }
  })
}

## M3: supplemental configurations (analysis_supplemental_experiments.R:179-186)
supp <- list(control = c(130, 80, 1, -1), gym = c(130, 80, 0.25, -1), timing = c(110, 60, 1, -1),
             gym_timing = c(110, 60, 0.25, -1), dT2X = c(130, 80, 1, 1), gym_timing_dT2X = c(110, 60, 0.25, 1))
n_s <- min(n_supp, n_main)
for (nm in names(supp)) {
  component(w, variant, "M3", workload = nm, function() {
    ref <- read_export(exports, paste0("legacy_supp_", nm, "_co2.csv"))
    run1 <- function(ii) model_run_supp(par_calib = S$constants[ii, ], par_time = par_time_of(ii),
                                        par_fixed = par_const_fixed0, parnames_calib = parnames_const_calib,
                                        parnames_fixed = parnames_const_fixed, parnames_time = parnames_time_calib,
                                        age = age, ageN = ageN, ind_const_calib = ind_const_calib,
                                        ind_time_calib = ind_time_calib, ind_const_fixed = ind_const_fixed,
                                        ind_time_fixed = ind_time_fixed, ind_expected_time = ind_expected_time,
                                        ind_expected_const = ind_expected_const,
                                        iteration_threshold = iteration_threshold,
                                        supp_experiment_parameters = supp[[nm]])
    for (ii in seq_len(min(20, n_s))) run1(ii)   # warm-up
    co2 <- matrix(NA_real_, n_s, ageN)
    c0 <- cpu_now(); t0 <- now()
    for (ii in seq_len(n_s)) co2[ii, ] <- run1(ii)[, "co2"]
    wall <- now() - t0; cpu <- cpu_now() - c0
    check_outputs(paste("R supp", nm), co2, ref[seq_len(n_s), , drop = FALSE], exact = exact)
    record(w, variant, "M3", wall / n_s, subcomponent = "model_run_supp", workload = nm, n = n_s,
           cpu_s = cpu / n_s, notes = "seconds per call")
  })
}
record(w, variant, "S2", setup_s, subcomponent = "legacy setup (model_setup.R, constraints.R)", mode = "first_call",
       peak_rss_bytes = peak_rss())
