## pipeline_x1.R: end-to-end run for X1 (plan §3.9), in a fresh process started by
## run_timing.jl (which measures the whole process from outside):
##   packages -> lhs.R (setup, precalibration until n_accept accepted, save) ->
##   analysis_and_plots.R (generated copy) on the shared ensemble -> figures
t_start <- proc.time()[["elapsed"]]
## analysis_and_plots.R starts with rm(list = ls()): the harness lives on an attached
## environment so that line does not remove it (see bench_analysis.R).
.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
.H <- attach(NULL, name = "geocarb_timing_harness")
sys.source(file.path(.this_dir, "..", "lib", "common.R"), envir = .H)
local(envir = .H, {
  job <- read_job(commandArgs(trailingOnly = TRUE)[1])
  w <- raw_writer(job)
  variant <- jstr(job, "variant", "R0")
  legacy_root <- normalizePath(jstr(job, "legacy_dir"), winslash = "/"); instr <- jstr(job, "instrumented_dir")
  thr <- jnum(job, "threshold"); k <- jint(job, "n_accept"); ch <- jint(job, "chunk"); seed <- jint(job, "seed")
  out <- jstr(job, "tmp_dir"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
  wl <- sprintf("threshold=%g accept=%d", thr, k)
  ## formals must not be a prefix of record()'s arguments: with function(name, t, ...),
  ## stage(..., n = 500) partially matched n to `name` and shuffled the columns of the row
  stage <- function(stage_label, stage_seconds, ...)
    record(w, variant, "X1", stage_seconds, subcomponent = stage_label, workload = wl, mode = "cold", ...)
  ceil <- ceiling                                                       # finding F-13
  g <- globalenv()
})
m <- measure(load_legacy_packages); suppressPackageStartupMessages(library(Hmisc))
stage("load package", m$wall)
setwd(file.path(legacy_root, "R"))
g$use_co2 <- TRUE; g$use_temperature <- TRUE; g$param_choice <- "all"; g$data_choice <- "F2017"; g$fSR_choice <- "DT2019"
g$prcout_threshold <- thr; g$n_sample <- jint(job, "n_cap"); g$n_sample_per_chunk <- ch; g$n_sample_min <- k
g$output_dir <- paste0(out, "/"); g$.LHS_SAMPLING_FILE <- file.path(instr, "lhs_sampling_timed.R")
g$.tm_now <- if (requireNamespace("bench", quietly = TRUE)) bench::hires_time else function() proc.time()[["elapsed"]]
set.seed(seed)
sys.source(file.path(instr, "lhs_timed.R"), envir = g)
check(nrow(g$par_calib_save) == k, "X1: not enough samples accepted")
stage("setup", sum(g$.tmS[c("setup", "first_model_run", "constraints", "bounds")]))
stage("precalibration", g$.tmS[["sampling"]], n = g$n_simulated, notes = sprintf("n_simulated=%d", g$n_simulated))
stage("save", sum(g$.tmS[c("save_covar", "save_param", "save_model")]))
## analysis_and_plots.R needs >= 3334 samples per ensemble (finding N-2), more than a
## short precalibration produces, so the analysis stage reads the shared ensemble.
.H$param_file <- jstr(job, "ensemble_rdata")
check(file.exists(.H$param_file), paste("missing", .H$param_file))
g$.LEGACY_R_DIR <- file.path(legacy_root, "R"); g$.NUM_SAMPLES <- jint(job, "num_samples"); g$.FIG_DIR <- file.path(out, "figures")
g$.OUT_DIR <- out; g$.ENSEMBLE <- function(dd, bb, seed = NULL) .H$param_file
dir.create(g$.FIG_DIR, showWarnings = FALSE)
sys.source(file.path(instr, "analysis_and_plots_timed.R"), envir = g)
acc <- g$.TM$acc
fig <- sum(unlist(acc[startsWith(names(acc), "G2")]))
stage("analysis", sum(unlist(acc)) - fig)
stage("figures", fig)
for (kk in names(acc)) record(w, variant, "X1", acc[[kk]], subcomponent = paste("analysis section:", kk), workload = wl, mode = "cold", n = k)
