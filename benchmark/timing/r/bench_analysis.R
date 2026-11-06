## bench_analysis.R: R side of analysis (A1-A6) and graphics (G2, G3) on the shared
## ensemble (plan §3.7-3.8, §5.3), using the generated copy of analysis_and_plots.R:
##   * the machine-specific setwd() is replaced by the harness's legacy tree;
##   * every lhs_param_*.RData load reads the shared ensemble;
##   * figures go to the benchmark's figure folder;
##   * the supplemental + Cretaceous part (lines 762-821) is left out.
## On the first repetition, the plain copy (path edits only) and the timed copy run with the
## same seed at a small num_samples and every object they create must be identical().
## analysis_and_plots.R starts with rm(list = ls()), so the harness lives on an attached
## environment (helpers, settings and the ceil shim) and is not touched by that line.
.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
.H <- attach(NULL, name = "geocarb_timing_harness")
sys.source(file.path(.this_dir, "..", "lib", "common.R"), envir = .H)
local(envir = .H, {
  job <- read_job(commandArgs(trailingOnly = TRUE)[1])
  w <- raw_writer(job)
  variant <- jstr(job, "variant", "R0")
  legacy_root <- normalizePath(jstr(job, "legacy_dir"), winslash = "/")
  instr <- jstr(job, "instrumented_dir")
  num <- jint(job, "num_samples")
  verify_n <- jint(job, "verify_n", 0L)
  seed <- jint(job, "seed", 2026L)
  fig_root <- jstr(job, "fig_dir"); out_dir <- jstr(job, "out_dir")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  wl <- sprintf("ensemble n=%d, 15 experiments", num)
  ceil <- ceiling                                                       # finding F-13
  g <- globalenv()
  run_copy <- function(file, n, figdir) {
    g$.LEGACY_R_DIR <- file.path(legacy_root, "R")
    g$.ENSEMBLE <- function(dd, bb, seed = NULL) jstr(job, "ensemble_rdata")
    g$.tm_now <- if (requireNamespace("bench", quietly = TRUE)) bench::hires_time else function() proc.time()[["elapsed"]]
    g$.NUM_SAMPLES <- n; g$.FIG_DIR <- figdir; g$.OUT_DIR <- out_dir
    dir.create(figdir, recursive = TRUE, showWarnings = FALSE)
    rm(list = ls(g), envir = g)
    set.seed(seed)
    t0 <- g$.tm_now()
    sys.source(file, envir = g)
    g$.tm_now() - t0
  }
  snapshot <- function() { k <- ls(g); k <- k[!vapply(k, function(x) is.function(get(x, g)), TRUE)]; mget(k, envir = g) }
})
suppressPackageStartupMessages({ library(lhs); library(CholWishart); library(MASS); library(abind); library(Hmisc) })

## The legacy analysis needs num_samples equal to the ensemble size (the time-series
## correlations pair vectors of both lengths) and at least 10 000 rows in the merged 30 %
## experiment (deltaT2X_samplesize); run_timing.jl ensures both.
.H$figdir <- file.path(fig_root, sprintf("R_rep%d", w$rep))
if (verify_n > 0) {
  component(w, variant, "B3", workload = sprintf("analysis num_samples=%d", num), function() {
    tp <- run_copy(file.path(instr, "analysis_and_plots_plain.R"), num, file.path(fig_root, "R_verify_plain"))
    .H$plain <- snapshot()
    record(w, variant, "A", tp, subcomponent = "analysis_and_plots.R total (plain copy)", workload = wl, n = num)
  })
}

component(w, variant, "A", workload = wl, function() {
  total <- run_copy(file.path(instr, "analysis_and_plots_timed.R"), num, .H$figdir)
  acc <- g$.TM$acc
  for (k in names(acc)) {
    record(w, variant, strsplit(k, " ")[[1]][1], acc[[k]], subcomponent = k, workload = wl, n = num)
  }
  record(w, variant, "A", total, subcomponent = "analysis_and_plots.R total (timed copy)", workload = wl, n = num,
         peak_rss_bytes = peak_rss())
  for (f in list.files(.H$figdir, pattern = "\\.pdf$", full.names = TRUE)) {
    record(w, variant, "G3", NA, subcomponent = paste("G2", sub("\\.pdf$", "", basename(f))), workload = wl, n = num,
           alloc_bytes = file.size(f), notes = "file size in alloc_bytes")
  }
  q <- g$par_quantiles[["30"]][["c"]]["deltaT2X", ]
  writeLines(c("quantity,value", sprintf("deltaT2X_c_out30_q%s,%.17g", names(q), q)),
             file.path(out_dir, sprintf("R_numbers_rep%d.csv", w$rep)))
  if (!is.null(.H$plain)) {
    b <- snapshot(); a <- .H$plain
    check(identical(sort(names(a)), sort(names(b))), "plain and timed copies create different objects")
    diff <- names(a)[!vapply(names(a), function(k) identical(a[[k]], b[[k]]), TRUE)]
    check(length(diff) == 0, paste("timed copy changed:", paste(head(diff, 10), collapse = ", ")))
    record(w, variant, "B3", NA, subcomponent = "analysis: timed copy identical to plain copy", workload = wl, n = num,
           notes = sprintf("identical() on %d objects", length(a)))
  }
})
