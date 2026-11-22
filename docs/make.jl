# Build the documentation (HTML + doctests):
#   julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
#   julia --project=docs docs/make.jl
#
# Environment variables:
#   CI=true            pretty URLs and deployment (set by GitHub Actions)
#   LINKCHECK=true     also check external links (the weekly workflow sets it)
#   DOCS_REPO          deployment target; defaults to github.com/$GITHUB_REPOSITORY.git
#   DOCS_DEPLOY=false  build (and doctest) on CI without deploying
#
# Regenerate doctest output after an intended change:
#   julia --project=docs -e 'using Documenter, GeocarbPrecalibration;
#       DocMeta.setdocmeta!(GeocarbPrecalibration, :DocTestSetup, :(using GeocarbPrecalibration); recursive=true);
#       doctest(GeocarbPrecalibration; fix=true)'
using Documenter
using GeocarbPrecalibration

const ROOT = normpath(joinpath(@__DIR__, ".."))
const ONCI = get(ENV, "CI", "false") == "true"

DocMeta.setdocmeta!(GeocarbPrecalibration, :DocTestSetup, :(using GeocarbPrecalibration); recursive=true)

# AI_USAGE.md at the repository root is the single source of the AI usage report; the
# documentation page is generated from it (and is git-ignored).
let src = joinpath(ROOT, "AI_USAGE.md"), dst = joinpath(@__DIR__, "src", "ai_usage.md")
    isfile(src) || error("AI_USAGE.md is missing: the AI usage report is required (JOSS)")
    write(dst, """
        ```@meta
        EditURL = "../../AI_USAGE.md"
        ```
        """ * read(src, String))
end

# The notebook tour (notebooks/tour.jl, Literate.jl format) is also a page of the
# documentation, with its outputs and figures. Running it takes 15-30 minutes, CairoMakie,
# the whole test suite and (for level C) R, so the build does not run it: the page in
# docs/src/generated/ is produced on a developer's machine with
#   julia --project=notebooks -t auto notebooks/build.jl --docs-page
# and committed. This check FAILS the build if tour.jl or tour_helpers.jl changed since
# then (or the page was made in quick mode), and warns if src/, ext/, data/,
# experiments/, test/ or Project.toml changed (see notebooks/tour_stamp.jl).
include(joinpath(ROOT, "notebooks", "tour_stamp.jl"))
let (errors, warnings) = TourStamp.check(ROOT)
    TourStamp.report(errors, warnings)
    isempty(errors) || error("the notebook-tour page is stale or missing; see the message above")
end

makedocs(;
    sitename="GeocarbPrecalibration.jl",
    modules=[GeocarbPrecalibration],
    format=Documenter.HTML(; prettyurls=ONCI, edit_link="main"),
    pages=[
        "Home" => "index.md",
        "Notebook tour" => "generated/notebook_tour.md",
        "The model" => "model.md",
        "Parameters" => "parameters.md",
        "Precalibration" => "precalibration.md",
        "Experiments" => "experiments.md",
        "Temperature conventions" => "temperature_conventions.md",
        "Testing" => "testing.md",
        "Performance" => "performance.md",
        "Porting notes" => "porting_notes.md",
        "AI usage" => "ai_usage.md",
        "API" => "api.md",
    ],
    doctest=true,
    linkcheck=get(ENV, "LINKCHECK", "false") == "true",
    checkdocs=:exports,
)

if ONCI && get(ENV, "DOCS_DEPLOY", "true") == "true"
    repo = get(
        ENV, "DOCS_REPO", "github.com/" * get(ENV, "GITHUB_REPOSITORY", "OWNER/GeocarbPrecalibration.jl") * ".git"
    )
    deploydocs(; repo=repo, devbranch="main", push_preview=true)
end
