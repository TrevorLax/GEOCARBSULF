#!/usr/bin/env julia
#
# One-time setup for the notebook tour. From the repository folder:
#
#   julia notebooks/setup.jl                 # everything below
#   julia notebooks/setup.jl --no-kernel     # skip installing the Jupyter kernel
#
# 1. instantiates the package environment (the test-suite cells run Pkg.test() in it);
# 2. creates the notebook environment in notebooks/: this checkout of the package
#    (Pkg.develop, so the notebook always uses the code next to it), CairoMakie,
#    IJulia, Literate; then precompiles it (several minutes the first time, mostly
#    CairoMakie);
# 3. installs a Jupyter kernel "GeocarbPrecalibration" that starts this Julia with the
#    notebook environment and all CPU threads;
# 4. writes notebooks/GeocarbPrecalibration_tour.ipynb from notebooks/tour.jl.
#
# Run it again with another Julia version (for example `julia +1.10 notebooks/setup.jl`)
# to get a kernel for that version; the kernel name includes the version.
# notebooks/Manifest.toml is not committed: each machine resolves its own.

using Pkg

const ROOT = normpath(joinpath(@__DIR__, ".."))
const NB = @__DIR__

println("1/4  package environment: ", ROOT)
Pkg.activate(ROOT)
Pkg.instantiate()

println("2/4  notebook environment: ", NB)
Pkg.activate(NB)
Pkg.develop(PackageSpec(; path=ROOT))
Pkg.instantiate()
Pkg.precompile()

if "--no-kernel" in ARGS
    println("3/4  Jupyter kernel: skipped (--no-kernel)")
else
    println("3/4  Jupyter kernel")
    @eval using IJulia
    Base.invokelatest(
        IJulia.installkernel, "GeocarbPrecalibration", "--project=$NB"; env=Dict("JULIA_NUM_THREADS" => "auto")
    )
end

println("4/4  notebook")
include(joinpath(NB, "build.jl"))
Base.invokelatest(main, String[])

println("""

        Done. Open notebooks/GeocarbPrecalibration_tour.ipynb in JupyterLab or VS Code and choose the
        kernel "GeocarbPrecalibration". Without a Jupyter installation:
            julia --project=notebooks -e "using IJulia; jupyterlab(dir=pwd())"
        """)
