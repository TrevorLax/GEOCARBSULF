## sentinel.R: fixed calibration kernel (plan §6.4), the R twin of sentinel.jl.
.this_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(.this_dir, "..", "lib", "common.R"))
job <- read_job(commandArgs(trailingOnly = TRUE)[1])
w <- raw_writer(job)
scalar_kernel <- compiler::cmpfun(function(n) { s <- 0; for (i in 1:n) s <- s + log(1 + exp(-i * 1e-7)); s })
A <- outer(1:200, 1:200, function(i, j) sin(i + j)); B <- A
scalar_kernel(10); A %*% B
for (k in list(list("exp/log loop (2x10^6)", function() scalar_kernel(2e6)),
               list("200x200 matmul x50", function() for (r in 1:50) A %*% B))) {
  t <- min(vapply(1:5, function(i) measure(k[[2]])$wall, 0))
  record(w, "R0", "SENT", t, subcomponent = k[[1]], workload = jstr(job, "position"), notes = "minimum of 5")
}
