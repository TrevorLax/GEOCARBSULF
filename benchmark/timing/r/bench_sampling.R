## bench_sampling.R: R side of the sampling components (plan §3.3)
##   P1  lhs::randomLHS(n, 56)
##   P2  the constant transform of lhs_sampling.R (rescale + qnorm/qlnorm), run from the
##       original file
##   P3  time-series sampling of one chunk, split into inverse-Wishart draws, MvNormal
##       draws and normalisation (the block of the generated lhs_sampling_timed.R)
##   P4  covariance storage (filling the 58 x 58 x n x 12 array and abind-ing it)
##   P5  raw RNG throughput
.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(.this_dir, "..", "lib", "common.R"))
job <- read_job(commandArgs(trailingOnly = TRUE)[1])
w <- raw_writer(job)
variant <- jstr(job, "variant", "R0")
legacy_root <- jstr(job, "legacy_dir")
exports <- jstr(job, "exports_dir")
instr <- jstr(job, "instrumented_dir")
mem_limit <- jnum(job, "memory_limit_bytes")

load_legacy_packages()
legacy_setup(legacy_root)
n_parameters <- length(parnames_const_calib)
n_parameters_time <- length(parnames_time_calib)
eval_lines(extract_block("lhs.R", "bounds <- mat.or.vec(nr=length(ind_const_calib), nc=2)", "source(\"lhs_sampling.R\")"))
source("time_series_df.R")
transform_block <- parse_block(extract_block("lhs_sampling.R", "# constant parameter sampling", "# divide the scalar parameters across the chunks"))
ts_block <- parse_block(extract_block(file.path(instr, "lhs_sampling_timed.R"), ".tm_u <- .tm_now()",
                          ".tmA[['ts_block']] <- .tmA[['ts_block']] + (.tm_now() - .tm_u)", include_to = TRUE,
                          after = "for (cc in 1:n_chunk) {"))
.tm_now <- if (requireNamespace("bench", quietly = TRUE)) bench::hires_time else function() proc.time()[["elapsed"]]

## P1 + P2
for (n in jints(job, "lhs_sizes")) {
  component(w, variant, "P1", workload = paste0("n=", n), function() {
    randomLHS(100, n_parameters)                           # warm-up
    m <- measure(function() randomLHS(n, n_parameters))
    check(all(dim(m$value) == c(n, n_parameters)) && all(m$value > 0 & m$value < 1), "randomLHS: bad design")
    record(w, variant, "P1", m$wall, subcomponent = "randomLHS", workload = paste0("n=", n), n = n, cpu_s = m$cpu)
    g <- globalenv(); g$parameters_lhs <- m$value
    m2 <- measure(function() eval_block(transform_block))
    check(all(dim(g$par_calib_tmp) == c(n, n_parameters)) && all(is.finite(g$par_calib_tmp)), "transform: non-finite values")
    record(w, variant, "P2", m2$wall, subcomponent = "rescale + qnorm/qlnorm (lhs_sampling.R)", workload = paste0("n=", n),
           n = n, cpu_s = m2$cpu)
  })
}
## P2 guard: with the seed of run_legacy.R the transform reproduces the exported values exactly
component(w, variant, "P2-guard", function() {
  set.seed(jint(job, "legacy_seed", 2026L))
  g <- globalenv(); g$parameters_lhs <- randomLHS(1000, n_parameters)
  eval_block(transform_block)
  ref <- read_export(exports, "legacy_lhs_values.csv")
  check(max(abs(g$par_calib_tmp - ref) / pmax(abs(ref), 1e-300)) <= 1e-12, "transform does not reproduce legacy_lhs_values.csv")
})

## P3: one chunk of time-series sampling, split into stages
n3 <- jint(job, "sampler_n")
component(w, variant, "P3", workload = paste0("n=", n3), function() {
  g <- globalenv()
  run_chunk <- function(n) {
    g$cc <- 1L; g$n_sample_this_chunk <- n
    g$.tmA <- c(ts_alloc = 0, iw = 0, mvn = 0, normalise = 0, ts_block = 0)
    eval_block(ts_block)
  }
  run_chunk(20)                                              # warm-up
  m <- measure(function() run_chunk(n3))
  ts <- g$time_series_samples
  check(all(dim(ts) == c(n_time, n3, n_parameters_time)), "time series: bad dimensions")
  pn <- colnames(par_time_center)
  for (k in which(pn %in% c("fR", "fL", "fA", "fAw_fA", "fC"))) check(all(abs(ts[n_time, , k] - 1) < 1e-12), paste(pn[k], "not 1 at present"))
  check(all(ts[n_time, , match("GEOG", pn)] == 0), "GEOG not 0 at present")
  for (st in c("ts_alloc", "iw", "mvn", "normalise")) {
    record(w, variant, "P3", g$.tmA[[st]] / n3, subcomponent = c(ts_alloc = "allocate arrays", iw = "inverse-Wishart draws (rInvWishart)",
           mvn = "MvNormal draws (mvrnorm)", normalise = "normalisation")[[st]], workload = paste0("n=", n3), n = n3,
           notes = "seconds per sample (12 forcings)")
  }
  record(w, variant, "P3", m$wall / n3, subcomponent = "total (inverse Wishart + MvNormal)", workload = paste0("n=", n3),
         n = n3, cpu_s = m$cpu / n3, notes = "seconds per sample (12 forcings)")
})

## P4: covariance storage
for (n in jints(job, "covariance_n")) {
  need <- 3 * 8 * n_time * n_time * n * n_parameters_time
  if (need > mem_limit) {
    record(w, variant, "P4", NA, workload = paste0("n=", n), n = n, checksum_ok = TRUE,
           notes = sprintf("skipped by the memory guard: needs about %.1f GB", need / 1e9))
    next
  }
  component(w, variant, "P4", workload = paste0("n=", n), function() {
    m1 <- measure(function() array(dim = c(n_time, n_time, n, n_parameters_time)))
    cov <- m1$value
    m2 <- measure(function() { for (pp in 1:n_parameters_time) cov[, , , pp] <- rInvWishart(n, df[pp], (df[pp] - (n_time + 1)) * diag(par_time_stdev[, pp]^2)); cov })
    cov <- m2$value
    m3 <- measure(function() abind(NULL, cov[, , seq_len(n), ], along = 3))
    check(all(dim(m3$value) == c(n_time, n_time, n, n_parameters_time)), "abind: bad dimensions")
    record(w, variant, "P4", m1$wall / n, subcomponent = "allocate covariance array", workload = paste0("n=", n), n = n,
           notes = sprintf("seconds per sample; array %.2f GB", as.numeric(object.size(cov)) / 1e9))
    record(w, variant, "P4", m2$wall / n, subcomponent = "fill (rInvWishart)", workload = paste0("n=", n), n = n,
           notes = "seconds per sample")
    record(w, variant, "P4", m3$wall / n, subcomponent = "store accepted (abind)", workload = paste0("n=", n), n = n,
           notes = "seconds per sample")
  })
}

## P5: raw RNG throughput
k <- jint(job, "rng_draws")
component(w, variant, "P5", function() {
  for (f in list(list("runif", function() runif(k)), list("rnorm", function() rnorm(k)),
                 list("rchisq(df = 60)", function() rchisq(k, 60)))) {
    m <- measure(f[[2]])
    record(w, variant, "P5", m$wall / k, subcomponent = f[[1]], n = k, cpu_s = m$cpu / k, notes = "seconds per draw")
  }
})
