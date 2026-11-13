# pre-push hook `golden-regression`: run one test group of test/runtests.jl.
#
#   julia --startup-file=no --project=. scripts/dev/test_group.jl GROUP
#
# GROUP is one of the groups listed at the top of test/runtests.jl (for example
# `regression`, the golden-master check against the compiled Fortran).

using Pkg
length(ARGS) == 1 || error("usage: test_group.jl GROUP")
Pkg.test(; test_args=ARGS)
