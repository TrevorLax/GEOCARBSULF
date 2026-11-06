## bench_engine.R: R side of the precalibration engine (plan §3.5)
##   mode = fixed      E2 fixed work (n_sample_min > n_sample) and the E1 breakdown from
##                     the generated lhs_sampling_timed.R; at n <= verify_n the original
##                     lhs_sampling.R runs too, with the same seed, and every saved object
##                     must be identical() (plan §6.8)
##   mode = realistic  E3: stop after n_accept_min accepted samples
##   mode = memory     E5: global LHS over n_sample, then one chunk; peak memory
.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(.this_dir, "..", "lib", "common.R"))
job <- read_job(commandArgs(trailingOnly = TRUE)[1])
w <- raw_writer(job)
variant <- jstr(job, "variant", "R0")
legacy_root <- jstr(job, "legacy_dir")
instr <- jstr(job, "instrumented_dir")
mode <- jstr(job, "mode", "fixed")
seed <- jint(job, "seed", 2026L)
tmp_out <- jstr(job, "tmp_dir")
dir.create(tmp_out, recursive = TRUE, showWarnings = FALSE)

load_legacy_packages()
setwd(file.path(legacy_root, "R"))
if (!exists("ceil")) ceil <- ceiling                     # finding F-13
.tm_now <- if (requireNamespace("bench", quietly = TRUE)) bench::hires_time else function() proc.time()[["elapsed"]]

SAVED <- c("parameters_lhs", "par_calib_save", "par_time_save", "par_covar_save", "co2_save", "temp_save", "o2_save",
           "prcout_co2_save", "prcout_temp_save", "n_simulated")

## Run lhs.R (generated copy) once with the given settings; returns wall time and objects.
run_lhs <- function(n, chunk, threshold, n_min, timed, seed) {
  g <- globalenv()
  g$use_co2 <- TRUE; g$use_temperature <- TRUE
  g$param_choice <- "all"; g$data_choice <- "F2017"; g$fSR_choice <- "DT2019"; g$n_node <- 1
  g$prcout_threshold <- threshold; g$n_sample <- n; g$n_sample_per_chunk <- chunk; g$n_sample_min <- n_min
  g$output_dir <- paste0(tmp_out, "/")
  ## the original lhs_sampling.R is sourced through a two-line wrapper that only reads the clock
  wrapper <- file.path(tmp_out, "time_original_lhs_sampling.R")
  writeLines(c(".t_orig <- .tm_now()", "source(\"lhs_sampling.R\")", ".t_orig <- .tm_now() - .t_orig"), wrapper)
  g$.LHS_SAMPLING_FILE <- if (timed) file.path(instr, "lhs_sampling_timed.R") else wrapper
  set.seed(seed)
  t0 <- .tm_now()
  sys.source(file.path(instr, if (timed) "lhs_timed.R" else "lhs_plain.R"), envir = g)
  wall <- .tm_now() - t0
  objs <- mget(SAVED, envir = g)
  list(wall = wall, objs = objs, tmS = if (timed) g$.tmS else NULL, tmA = if (timed) g$.tmA else NULL,
       sampling = if (timed) g$.tmS[["sampling"]] else g$.t_orig)
}

E1_LABELS <- c(time_series_df = "setup: time_series_df.R", lhs = "constants: LHS", transform = "constants: transform",
               split_chunks = "constants: split into chunks", init = "init", ts_alloc = "time series: allocate",
               iw = "time series: inverse Wishart", mvn = "time series: MvNormal", normalise = "time series: normalise",
               model_alloc = "model: allocate", model = "model", store = "model: store outputs", prcout = "percent outbound",
               accept = "acceptance", append = "store accepted (rbind/abind)")

record_breakdown <- function(r, n, workload) {
  a <- r$tmA
  for (k in names(E1_LABELS)) {
    record(w, variant, "E1", a[[k]], subcomponent = E1_LABELS[[k]], workload = workload, n = n)
  }
  inner <- a[["ts_block"]] + a[["model_block"]] + a[["accept"]] + a[["append"]]
  record(w, variant, "E1", a[["chunk_loop"]] - inner, subcomponent = "orchestration (chunk loop minus blocks)",
         workload = workload, n = n)
  record(w, variant, "E1", a[["ts_block"]] - (a[["ts_alloc"]] + a[["iw"]] + a[["mvn"]] + a[["normalise"]]),
         subcomponent = "time series: loop overhead", workload = workload, n = n)
  record(w, variant, "E1", a[["model_block"]] - (a[["model_alloc"]] + a[["model"]] + a[["store"]] + a[["prcout"]]),
         subcomponent = "model: loop overhead", workload = workload, n = n)
  s <- r$tmS
  for (k in c("setup", "first_model_run", "constraints", "bounds")) {
    record(w, variant, "E1", s[[k]], subcomponent = paste("lhs.R", k), workload = workload, n = n)
  }
}

chunk_for <- function(n, chunk) as.integer(min(chunk, ceiling(n / 2)))   # at least two chunks (F-12)

if (mode == "fixed") {
  thr <- jnum(job, "threshold")
  verify_n <- jint(job, "verify_n")
  for (n in jints(job, "sizes")) {
    ch <- chunk_for(n, jint(job, "chunk"))
    wl <- sprintf("n=%d chunk=%d threshold=%g", n, ch, thr)
    need <- 3 * 8 * n * 56 + 8 * ch * 12 * (58 * 58 + 58) + 4e8
    if (need > jnum(job, "memory_limit_bytes")) {
      record(w, variant, "E2", NA, workload = wl, n = n, notes = sprintf("skipped by the memory guard (about %.1f GB)", need / 1e9))
      next
    }
    component(w, variant, "E2", workload = wl, function() {
      timed <- run_lhs(n, ch, thr, n + 1, TRUE, seed)
      check(timed$objs$n_simulated == n, "fixed work: n_simulated != n_sample")
      ## E2 = lhs_sampling.R itself (setup and save excluded), as for Julia's run_precalibration
      if (n <= verify_n) {
        plain <- run_lhs(n, ch, thr, n + 1, FALSE, seed)
        same <- vapply(SAVED, function(k) identical(plain$objs[[k]], timed$objs[[k]]), TRUE)
        check(all(same), paste("instrumented copy changed:", paste(SAVED[!same], collapse = ", ")))
        record(w, variant, "E2", timed$sampling, subcomponent = "lhs_sampling.R (instrumented copy)", workload = wl, n = n,
               peak_rss_bytes = peak_rss())
        record(w, variant, "E2", plain$sampling, subcomponent = "lhs_sampling.R (original)", workload = wl, n = n)
        record(w, variant, "B3", timed$sampling / plain$sampling - 1, subcomponent = "instrumentation overhead (fraction)",
               workload = wl, n = n, notes = sprintf("original %.3f s, instrumented %.3f s; identical() on %d objects",
                                                     plain$sampling, timed$sampling, length(SAVED)))
      } else {
        record(w, variant, "E2", timed$sampling, subcomponent = "lhs_sampling.R (instrumented copy)", workload = wl,
               n = n, peak_rss_bytes = peak_rss())
      }
      record_breakdown(timed, n, wl)
    })
  }
} else if (mode == "realistic") {
  for (pair in jlist(job, "realistic")) {
    v <- as.numeric(strsplit(pair, ":")[[1]]); thr <- v[1]; k <- as.integer(v[2]); cap <- as.integer(v[3])
    ch <- jint(job, "chunk")
    wl <- sprintf("threshold=%g accept=%d chunk=%d cap=%d", thr, k, ch, cap)
    component(w, variant, "E3", workload = wl, function() {
      r <- run_lhs(cap, ch, thr, k, TRUE, seed)
      check(nrow(r$objs$par_calib_save) == k, sprintf("only %d of %d accepted within n_sample = %d (lower realistic_min_rate)", nrow(r$objs$par_calib_save), k, cap))
      record(w, variant, "E3", r$sampling, subcomponent = "lhs_sampling.R (instrumented copy)", workload = wl,
             n = r$objs$n_simulated, peak_rss_bytes = peak_rss(),
             notes = sprintf("n_simulated=%d n_accepted=%d", r$objs$n_simulated, nrow(r$objs$par_calib_save)))
    })
  }
} else if (mode == "memory") {
  n <- jint(job, "n"); ch <- jint(job, "chunk")
  wl <- sprintf("GlobalLHS n=%d chunk=%d covariances=on", n, ch)
  component(w, variant, "E5", workload = wl, function() {
    r <- run_lhs(n, ch, 1.0, ch, TRUE, seed)
    record(w, variant, "E5", r$wall, subcomponent = "peak memory, global LHS + first chunk", workload = wl, n = n,
           peak_rss_bytes = peak_rss(), notes = "R always stores covariances (par_covar_save)")
  })
}
