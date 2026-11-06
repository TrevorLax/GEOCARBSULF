## Shared helpers for the R side of the timing benchmark: job files, the raw CSV
## writer (schema of TIMING_BENCHMARK_PLAN.md §7), timers, correctness guards and the
## legacy set-up. Mirrors lib/common.jl.
##
## Every R benchmark script is started by run_timing.jl as
##     Rscript <script> <job file>
## and appends one row per measurement to the raw CSV named in the job file.
## Nothing in legacy/ is modified: legacy scripts are sourced as they are, from a
## working directory inside the legacy tree, exactly as run_legacy.R does.

`%||%` <- function(a, b) if (is.null(a)) b else a

## ---- job files ---------------------------------------------------------------

read_job <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  kv <- regmatches(lines, regexpr("=", lines), invert = TRUE)
  job <- lapply(kv, function(x) trimws(x[2]))
  names(job) <- vapply(kv, function(x) trimws(x[1]), "")
  job
}
jstr <- function(job, k, default = NULL) {
  v <- job[[k]]
  if (is.null(v)) { if (is.null(default)) stop("job file: missing key '", k, "'") else return(default) }
  v
}
jint <- function(job, k, default = NULL) as.integer(gsub("_", "", jstr(job, k, if (is.null(default)) NULL else as.character(default))))
jnum <- function(job, k, default = NULL) as.numeric(jstr(job, k, if (is.null(default)) NULL else as.character(default)))
jbool <- function(job, k, default = FALSE) tolower(jstr(job, k, as.character(default))) %in% c("true", "1", "yes")
jints <- function(job, k) { s <- jstr(job, k, ""); if (!nzchar(s)) integer(0) else as.integer(gsub("_", "", strsplit(s, ",")[[1]])) }
jlist <- function(job, k) { s <- jstr(job, k, ""); if (!nzchar(s)) character(0) else strsplit(s, ",")[[1]] }

## ---- timers ------------------------------------------------------------------

.have_bench <- requireNamespace("bench", quietly = TRUE)
.have_ps <- requireNamespace("ps", quietly = TRUE)

## Wall clock in seconds; high resolution if the bench package is installed.
now <- if (.have_bench) function() as.numeric(bench::hires_time()) else function() proc.time()[["elapsed"]]
timer_note <- if (.have_bench) "" else "low-resolution timer (bench not installed)"
cpu_now <- function() { p <- proc.time(); p[["user.self"]] + p[["sys.self"]] }

## measure(f): wall and CPU time of one call of f(); returns list(wall, cpu, value)
measure <- function(f) {
  c0 <- cpu_now(); t0 <- now()
  v <- f()
  t1 <- now(); c1 <- cpu_now()
  list(wall = t1 - t0, cpu = c1 - c0, value = v)
}

## Peak memory of this process in bytes (NA if it cannot be read).
peak_rss <- function() {
  if (.Platform$OS.type == "windows") {
    if (.have_ps) {
      m <- tryCatch(ps::ps_memory_info(ps::ps_handle()), error = function(e) NULL)
      if (!is.null(m) && "peak_wset" %in% names(m)) return(as.numeric(m[["peak_wset"]]))
    }
    return(NA_real_)
  }
  f <- "/proc/self/status"
  if (file.exists(f)) {
    l <- grep("^VmHWM:", readLines(f), value = TRUE)
    if (length(l)) return(as.numeric(gsub("[^0-9]", "", l)) * 1024)
  }
  NA_real_
}

## ---- raw CSV writer ----------------------------------------------------------

RAW_HEADER <- c("impl", "variant", "component", "subcomponent", "workload", "n", "threads", "rep", "mode",
                "wall_s", "cpu_s", "gc_s", "compile_s", "alloc_bytes", "peak_rss_bytes", "checksum_ok",
                "session_id", "timestamp", "notes")
PER_SAMPLE_HEADER <- c("impl", "variant", "component", "rep", "sample", "group", "iterations", "n_failed",
                       "seconds", "session_id")

.csvfield <- function(x) {
  if (is.logical(x)) return(if (is.na(x)) "NA" else if (x) "true" else "false")
  if (is.numeric(x)) {
    if (is.na(x)) return("NA")
    if (x == round(x) && abs(x) < 1e15) return(format(x, scientific = FALSE, trim = TRUE))
    return(sprintf("%.9g", x))
  }
  x <- as.character(x)
  if (grepl("[\",\n]", x)) x <- paste0("\"", gsub("\"", "\"\"", x), "\"")
  x
}

raw_writer <- function(job) {
  w <- list(path = jstr(job, "raw_file"), per_sample = jstr(job, "per_sample_file"),
            session = jstr(job, "session_id"), rep = jint(job, "rep", 1L))
  for (p in list(c(w$path, paste(RAW_HEADER, collapse = ",")), c(w$per_sample, paste(PER_SAMPLE_HEADER, collapse = ",")))) {
    dir.create(dirname(p[1]), recursive = TRUE, showWarnings = FALSE)
    if (!file.exists(p[1])) writeLines(p[2], p[1])
  }
  w
}

record <- function(w, variant, component, wall_s, subcomponent = "", workload = "", n = 1, threads = 1,
                   rep = w$rep, mode = "warm", cpu_s = NA, gc_s = NA, compile_s = NA, alloc_bytes = NA,
                   peak_rss_bytes = NA, checksum_ok = TRUE, notes = "") {
  if (!nzchar(notes) && nzchar(timer_note)) notes <- timer_note
  row <- list("R", variant, component, subcomponent, workload, n, threads, rep, mode, wall_s, cpu_s, gc_s,
              compile_s, alloc_bytes, peak_rss_bytes, checksum_ok, w$session,
              format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), notes)
  cat(paste(vapply(row, .csvfield, ""), collapse = ","), "\n", sep = "", file = w$path, append = TRUE)
  invisible(NULL)
}

record_per_sample <- function(w, variant, component, sample, group, iterations, n_failed, seconds) {
  row <- list("R", variant, component, w$rep, sample, group, iterations, n_failed, seconds, w$session)
  cat(paste(vapply(row, .csvfield, ""), collapse = ","), "\n", sep = "", file = w$per_sample, append = TRUE)
}

## ---- correctness guards ------------------------------------------------------

guard_error <- function(msg) structure(class = c("guard_error", "error", "condition"),
                                       list(message = msg, call = sys.call(-1)))
check <- function(cond, msg) if (!isTRUE(cond)) stop(guard_error(msg))

## component(w, variant, name, f): run f(); a failed guard or error becomes a row with
## checksum_ok = FALSE and does not stop the other components.
component <- function(w, variant, name, f, workload = "") {
  t0 <- now()
  res <- tryCatch({ f(); TRUE }, error = function(e) {
    msg <- substr(gsub("\n", " ", conditionMessage(e)), 1, 300)
    message("R ", variant, " ", name, " FAILED: ", msg)
    record(w, variant, name, NA, workload = workload, checksum_ok = FALSE, notes = msg)
    FALSE
  })
  if (res) message(sprintf("R      %-10s %-14s done in %.1f s", variant, name, now() - t0))
  invisible(res)
}

## Inf/NaN positions identical; finite values equal (exact) or within tolerances
## (rtol before a run's first failed step, rtol_post after it).
check_outputs <- function(label, got, ref, exact = TRUE, rtol = 1e-8, rtol_post = 1e-4, atol = 1e-10) {
  check(all(dim(got) == dim(ref)), paste0(label, ": dimensions differ"))
  special <- !is.finite(got) | !is.finite(ref)
  same_special <- (is.nan(got) == is.nan(ref)) & (is.na(got) == is.na(ref)) &
                  ((is.infinite(got) & is.infinite(ref) & got == ref) | (!is.infinite(got) & !is.infinite(ref)))
  nmask <- sum(special & !same_special, na.rm = TRUE)
  check(nmask == 0, paste0(label, ": ", nmask, " Inf/NaN/NA positions differ from the reference"))
  fin <- !special
  if (exact) {
    nbad <- sum(got[fin] != ref[fin])
  } else {
    post <- t(apply(is.infinite(ref), 1, cumsum)) > 0
    tol <- ifelse(post, rtol_post, rtol)
    nbad <- sum(abs(got[fin] - ref[fin]) > atol + tol[fin] * pmax(abs(got[fin]), abs(ref[fin])))
  }
  check(nbad == 0, paste0(label, ": ", nbad, " finite values differ", if (exact) " (exact match required)" else ""))
  invisible(TRUE)
}

## ---- legacy set-up -----------------------------------------------------------

## Source the legacy set-up exactly as lhs.R does (model_setup.R, percent_outbound.R,
## constraints.R), with the settings of run_legacy.R. Everything is created in the
## global environment, as the legacy scripts expect. Returns the wall time.
legacy_setup <- function(legacy_root) {
  setwd(file.path(legacy_root, "R"))
  if (!exists("ceil", envir = globalenv())) assign("ceil", ceiling, envir = globalenv())  # finding F-13
  g <- globalenv()
  g$use_co2 <- TRUE; g$use_temperature <- TRUE
  g$param_choice <- "all"; g$data_choice <- "F2017"; g$fSR_choice <- "DT2019"; g$n_node <- 1
  g$filename.data <- "../input_data/CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv"
  t0 <- now()
  sys.source("model_setup.R", envir = g)
  sys.source("percent_outbound.R", envir = g)
  ## lhs.R runs the model once at the centres to get the time axis before constraints.R
  mo <- with(g, model_run(par_calib = par_calib0, par_time = par_time_center, par_fixed = par_fixed0,
                          parnames_calib = parnames_const_calib, parnames_fixed = parnames_const_fixed,
                          parnames_time = parnames_time_calib, age = age, ageN = ageN,
                          ind_const_calib = ind_const_calib, ind_time_calib = ind_time_calib,
                          ind_const_fixed = ind_const_fixed, ind_time_fixed = ind_time_fixed,
                          ind_expected_time = ind_expected_time, ind_expected_const = ind_expected_const,
                          iteration_threshold = iteration_threshold))
  g$n_time <- nrow(mo); g$time <- mo[, 1]
  sys.source("constraints.R", envir = g)
  now() - t0
}

## Read one of the 17-digit CSV exports of run_legacy.R as a numeric matrix.
read_export <- function(dir, file) {
  m <- as.matrix(utils::read.csv(file.path(dir, file), check.names = FALSE, colClasses = "numeric",
                                 na.strings = c("NA")))
  storage.mode(m) <- "double"
  m
}

## The 1000 legacy samples: constants (n x 56, named) and time series (n x 58 x 12 array,
## forcings in the column order of par_time_center).
legacy_samples_r <- function(exports_dir, n_time = 58L) {
  C <- read_export(exports_dir, "constants.csv")
  TS <- read_export(exports_dir, "time_series.csv")
  nm <- unique(sub("_[0-9]+$", "", colnames(TS)))
  arr <- array(NA_real_, dim = c(nrow(TS), n_time, length(nm)), dimnames = list(NULL, NULL, nm))
  for (k in seq_along(nm)) arr[, , k] <- TS[, ((k - 1) * n_time + 1):(k * n_time)]
  list(constants = C, series = arr)
}

## Stratification of plan §5.1 (clean / partial / heavy) from the legacy CO2 export.
sample_groups_r <- function(co2_ref) {
  nfail <- rowSums(is.infinite(co2_ref))
  cut <- stats::quantile(nfail, 0.9, type = 7)
  g <- ifelse(nfail == 0, "clean", ifelse(nfail >= cut & nfail > 0, "heavy", "partial"))
  list(group = g, n_failed = nfail)
}

## ---- legacy code blocks ----------------------------------------------------------
## Lines of a legacy (or generated instrumented) script between two anchor lines, so
## that a component can be timed by running the original code itself.
extract_block <- function(file, from, to, include_to = FALSE, after = NULL) {
  l <- readLines(file, warn = FALSE); t <- trimws(l)
  s0 <- if (is.null(after)) 1L else which(t == after)[1]
  if (is.na(s0)) stop(basename(file), ": 'after' anchor not found: ", after)
  i <- which(t == trimws(from)); i <- i[i >= s0][1]
  if (is.na(i)) stop(basename(file), ": block start not found: ", from)
  j <- which(t == trimws(to)); j <- j[j > i][1]
  if (is.na(j)) stop(basename(file), ": block end not found: ", to)
  l[i:(if (include_to) j else j - 1L)]
}
## Parse once, evaluate many times (parsing is not part of any timed component).
parse_block <- function(lines) parse(text = lines, keep.source = FALSE)
eval_block <- function(expr, envir = globalenv()) invisible(eval(expr, envir = envir))
eval_lines <- function(lines, envir = globalenv()) eval_block(parse_block(lines), envir)

## Load the R packages of lhs.R (S1 measures the same list in a cold process).
load_legacy_packages <- function() suppressPackageStartupMessages({
  library(lhs); library(CholWishart); library(abind); library(MASS)
})
