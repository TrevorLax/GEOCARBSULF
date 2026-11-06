## bench_constraints.R: R side of the constraint components (plan §3.4)
##   C1  percout() (percent_outbound.R) on the 1000 exported CO2 and temperature series
##   C2  the acceptance step of lhs_sampling.R:150-163 for one chunk
.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(.this_dir, "..", "lib", "common.R"))
job <- read_job(commandArgs(trailingOnly = TRUE)[1])
w <- raw_writer(job)
variant <- jstr(job, "variant", "R0")
exports <- jstr(job, "exports_dir")
load_legacy_packages()
legacy_setup(jstr(job, "legacy_dir"))

co2 <- read_export(exports, "legacy_co2.csv")
temp <- read_export(exports, "legacy_temp_plus15.csv")
ref <- read_export(exports, "legacy_prcout.csv")
n <- nrow(co2)
reps <- 20L

component(w, variant, "C1", workload = paste0("legacy_", n), function() {
  pc <- pt <- numeric(n)
  one <- function() for (i in 1:n) { pc[i] <<- percout(co2[i, ], windows$co2); pt[i] <<- percout(temp[i, ], windows$temp) }
  one()
  m <- measure(function() for (r in 1:reps) one())
  check(identical(pc, ref[, "co2"]) && identical(pt, ref[, "temp"]), "percout does not reproduce legacy_prcout.csv")
  record(w, variant, "C1", m$wall / (2 * n * reps), subcomponent = "percout", workload = paste0("legacy_", n),
         n = 2 * n * reps, cpu_s = m$cpu / (2 * n * reps), notes = "seconds per series")
})

component(w, variant, "C2", workload = paste0("legacy_", n), function() {
  g <- globalenv()
  g$prcout_co2 <- ref[, "co2"]; g$prcout_temp <- ref[, "temp"]; g$prcout_threshold <- 0.5
  block <- parse_block(extract_block("lhs_sampling.R", "idx_save_temp <- which(prcout_temp <= prcout_threshold)",
                         "n_simulated <- n_simulated + n_sample_this_chunk[cc]"))
  eval_block(block)
  k <- 2000L
  m <- measure(function() for (r in 1:k) eval_block(block))
  check(length(g$idx_save) == sum(ref[, "co2"] <= 0.5 & ref[, "temp"] <= 0.5, na.rm = TRUE), "acceptance count differs")
  record(w, variant, "C2", m$wall / (k * n), subcomponent = "which/intersect (lhs_sampling.R:150-163)",
         workload = paste0("legacy_", n), n = k * n, cpu_s = m$cpu / (k * n),
         notes = "seconds per sample (block evaluated once per 1000-sample chunk)")
})
