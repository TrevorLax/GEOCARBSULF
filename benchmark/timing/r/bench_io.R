## bench_io.R: R side of output I/O (plan §3.6)
##   O1  save() of the three objects sets lhs.R writes (covariances, parameters, model output)
##   O2  load() of the same files
##   O3  the same save into a cloud-synced folder (only if synced_dir is set)
## The objects come from a run of the original lhs.R/lhs_sampling.R with every sample accepted.
.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(.this_dir, "..", "lib", "common.R"))
job <- read_job(commandArgs(trailingOnly = TRUE)[1])
w <- raw_writer(job)
variant <- jstr(job, "variant", "R0")
legacy_root <- jstr(job, "legacy_dir"); instr <- jstr(job, "instrumented_dir")
n <- jint(job, "io_n"); tmp <- jstr(job, "tmp_dir"); synced <- jstr(job, "synced_dir", "")
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
load_legacy_packages()
setwd(file.path(legacy_root, "R"))
if (!exists("ceil")) ceil <- ceiling
g <- globalenv()
g$use_co2 <- TRUE; g$use_temperature <- TRUE; g$param_choice <- "all"; g$data_choice <- "F2017"; g$fSR_choice <- "DT2019"
g$prcout_threshold <- 1.0; g$n_sample <- n; g$n_sample_per_chunk <- min(1000L, ceiling(n / 2)); g$n_sample_min <- n
g$output_dir <- paste0(tmp, "/"); g$.LHS_SAMPLING_FILE <- "lhs_sampling.R"
set.seed(1)
sys.source(file.path(instr, "lhs_plain.R"), envir = g)                # also writes the files once (warm-up)
check(nrow(par_calib_save) == n, "not every sample was accepted")
sets <- list(covariances = "par_covar_save", parameters = c("par_calib_save", "par_time_save"),
             model = c("time", "co2_save", "temp_save", "o2_save", "prcout_co2_save", "prcout_temp_save", "n_simulated"))
wl <- sprintf("n=%d accepted, covariances=on", n)
for (where in c("local", "synced")) {
  root <- if (where == "local") tmp else synced
  if (!nzchar(root)) next
  comp <- if (where == "local") "O1" else "O3"
  component(w, variant, comp, workload = wl, function() {
    d <- file.path(root, paste0("GeocarbTiming_io_", w$session, "_", variant)); dir.create(d, showWarnings = FALSE)
    for (s in names(sets)) {
      f <- file.path(d, paste0("lhs_", s, ".RData"))
      m <- measure(function() save(list = sets[[s]], file = f, envir = g))
      record(w, variant, comp, m$wall, subcomponent = paste("save()", s), workload = wl, n = n, cpu_s = m$cpu,
             notes = sprintf("file %.0f bytes; %s", file.size(f), where))
      if (where == "local") {
        e <- new.env()
        m <- measure(function() load(f, envir = e))
        check(all(sets[[s]] %in% ls(e)), paste("load() of", s, "is missing objects"))
        record(w, variant, "O2", m$wall, subcomponent = paste("load()", s), workload = wl, n = n, cpu_s = m$cpu)
      }
    }
    unlink(d, recursive = TRUE)
  })
}
