# pre-push hook `docs-build`: set up the docs environment (as Docs.yml does), then build.
#   julia --startup-file=no --project=docs scripts/dev/docs.jl
using Pkg
Pkg.develop(PackageSpec(; path=normpath(joinpath(@__DIR__, "..", ".."))))
Pkg.instantiate()
include(joinpath(@__DIR__, "..", "..", "docs", "make.jl"))
