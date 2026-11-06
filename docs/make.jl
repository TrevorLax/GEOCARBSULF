# Build the documentation:
#   julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
#   julia --project=docs docs/make.jl
using Documenter
using GeocarbPrecalibration

makedocs(;
    sitename = "GeocarbPrecalibration.jl",
    modules = [GeocarbPrecalibration],
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", "false") == "true"),
    pages = [
        "Home" => "index.md",
        "The model" => "model.md",
        "Parameters" => "parameters.md",
        "Precalibration" => "precalibration.md",
        "Experiments" => "experiments.md",
        "Temperature conventions" => "temperature_conventions.md",
        "Testing" => "testing.md",
        "Performance" => "performance.md",
        "Porting notes" => "porting_notes.md",
        "API" => "api.md",
    ],
    checkdocs = :exports,
    warnonly = [:missing_docs, :cross_references, :docs_block],
)

if get(ENV, "CI", "false") == "true"
    deploydocs(; repo = get(ENV, "DOCS_REPO", "github.com/OWNER/GeocarbPrecalibration.jl.git"), devbranch = "main")
end
