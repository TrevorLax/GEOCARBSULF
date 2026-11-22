#!/usr/bin/env julia
#
# Generate the notebook from its source, notebooks/tour.jl (Literate.jl format: lines
# starting with `# ` are Markdown, everything else is code).
#
#   julia --project=notebooks notebooks/build.jl
#       writes notebooks/GeocarbPrecalibration_tour.ipynb without outputs (commit this
#       one together with any change to tour.jl; the Notebook CI workflow checks it)
#
#   julia --project=notebooks notebooks/build.jl --execute [--hide-home] [--html]
#       runs every cell (15-30 min) into notebooks/executed/GeocarbPrecalibration_tour.ipynb,
#       which git ignores
#
# Options (combine freely):
#   --execute    run every cell and store the outputs, in notebooks/executed/
#   --hide-home  replace this machine's home folder with "~" wherever it appears in the
#                notebook (paths in tables, logs, versioninfo, R metadata), for example
#                C:\Users\you\code\... becomes ~\code\...; it does not remove anything
#                else (machine name in versioninfo, git commit, R and Julia versions)
#   --html       convert notebooks/executed/GeocarbPrecalibration_tour.ipynb into one
#                self-contained HTML file next to it, with
#                `jupyter nbconvert --to html --embed-images` (images embedded as base64)
#
# Without --execute, --hide-home and --html work on the executed notebook already in
# notebooks/executed/ (for example one you ran in JupyterLab and saved there).
#
# The "Notebook tour" page of the documentation, with outputs and figures:
#
#   julia --project=notebooks -t auto notebooks/build.jl --docs-page [--quick]
#       runs every cell (15-30 min; `-t auto` makes the precalibration faster) into
#       docs/src/generated/notebook_tour.md, with one PNG file per figure
#       (notebook_tour-<n>.png) and the stamp notebook_tour.stamp.toml; replaces the
#       home folder with "~" in the page; and rewrites the .ipynb without outputs as
#       above. Commit everything in docs/src/generated/ together with the .ipynb.
#       The Docs workflow only renders the committed page; docs/make.jl fails if
#       tour.jl or tour_helpers.jl changed since the page was generated (see
#       notebooks/tour_stamp.jl). Levels B and C run if this machine can run them,
#       as in the notebook, so the page shows what this machine found.
#   --quick      with --docs-page: quick mode (GEOCARB_NOTEBOOK_FAST=true), a few
#                minutes, to try the pipeline. docs/make.jl rejects a quick page, so
#                run without --quick before committing.
#
# --html needs Jupyter's nbconvert: the program named by the JUPYTER environment
# variable, else `jupyter` on the PATH, else the private Jupyter that IJulia installs
# (`using IJulia; jupyterlab()` offers to install it).
#
# The "Publish notebook" workflow (.github/workflows/PublishNotebook.yml) runs
# `--execute --hide-home --html` on a release tag with Julia 1.12.5, R and gfortran
# installed so that level C runs. Release.yml calls it before creating the release and
# attaches the .ipynb and the .html to the release before publishing it.

using Literate
using TOML

const NB_DIR = @__DIR__
const NB_NAME = "GeocarbPrecalibration_tour"
const NB_SRC = joinpath(NB_DIR, "tour.jl")
const EXECUTED_DIR = joinpath(NB_DIR, "executed")
const OPTIONS = ("--execute", "--hide-home", "--html", "--docs-page", "--quick")

const REPO_ROOT = normpath(joinpath(NB_DIR, ".."))
const DOCS_GEN = joinpath(REPO_ROOT, "docs", "src", "generated")
const DOCS_NAME = "notebook_tour"
const DOCS_FIGURE = Regex("^" * DOCS_NAME * raw"-\d+\.(png|svg|jpeg)$")
const DOCS_EDIT_URL = replace(relpath(NB_SRC, DOCS_GEN), '\\' => '/')   # "Edit on GitHub" link of the page
const RUN_INFO_MARK = "{{TOUR_RUN_INFO}}"   # placeholder in the `#md` note of tour.jl
const MAX_FIGURE_KB = 1000                  # check-added-large-files in .pre-commit-config.yaml

include(joinpath(NB_DIR, "tour_stamp.jl"))  # module TourStamp

"""
    hide_home!(path) -> Int

Replace the home folder with `~` in the notebook file `path`, in every spelling it can
have inside the JSON text (backslashes escaped once or twice, forward slashes), and
return the number of replacements.
"""
function hide_home!(path::AbstractString)
    home = rstrip(homedir(), ['/', '\\'])
    length(home) < 3 && error("home folder '$home' is too short to replace safely")
    text = read(path, String)
    forms = [home, replace(home, '\\' => '/'), replace(home, '\\' => "\\\\"), replace(home, '\\' => "\\\\\\\\")]
    n = 0
    for form in sort(unique(forms); by=length, rev=true)  # longest first: escaped forms contain the plain one
        k = count(form, text)
        k == 0 && continue
        text = replace(text, form => "~")
        n += k
    end
    write(path, text)
    return n
end

"""
    nbconvert_command() -> Cmd

`jupyter nbconvert`, from `ENV["JUPYTER"]`, the `PATH`, or IJulia's private Jupyter.
"""
function nbconvert_command()
    j = get(ENV, "JUPYTER", "")
    isfile(j) && return `$j nbconvert`
    j = Sys.which("jupyter")
    j !== nothing && return `$j nbconvert`
    cmd = try
        @eval using IJulia
        Base.invokelatest(IJulia.find_jupyter_subcommand, "nbconvert")
    catch
        nothing
    end
    if cmd === nothing || !isfile(first(cmd.exec))
        error(
            "Jupyter's nbconvert was not found. Install it (for example `pip install nbconvert`), " *
            "set the JUPYTER environment variable to the `jupyter` program, or let IJulia install " *
            "its own Jupyter with `julia --project=notebooks -e \"using IJulia; jupyterlab()\"`.",
        )
    end
    return cmd
end

"""
    to_html(notebook) -> String

One self-contained HTML file next to `notebook`, images embedded as base64.
"""
function to_html(notebook::AbstractString)
    base = nbconvert_command()
    args = ["--to", "html", "--embed-images", notebook, "--output-dir", dirname(notebook)]
    run(Cmd(Cmd(vcat(base.exec, args)); env=base.env))   # keep the environment IJulia's Jupyter needs
    return splitext(notebook)[1] * ".html"
end

"The notebook without outputs, notebooks/GeocarbPrecalibration_tour.ipynb (the committed one)."
function plain_notebook()
    p = Literate.notebook(NB_SRC, NB_DIR; name=NB_NAME, execute=false, credit=false)
    endswith(read(p, String), '\n') || open(io -> write(io, '\n'), p, "a")   # end-of-file-fixer hook
    return p
end

"""
    png_only!()

Make CairoMakie figures showable only as PNG. CairoMakie also offers `text/html` (a
base64 `<img>`) and SVG, and Literate's Documenter flavour tries `text/html` first, so
without this every figure would be embedded in the Markdown file instead of written
to its own PNG file (and an SVG of a 58 000-point scatter plot is several MB).
"""
function png_only!()
    @eval using CairoMakie
    # the binding was created in a newer world than this call: reach it with invokelatest
    return Base.invokelatest(_png_only!, Base.invokelatest(getfield, @__MODULE__, :CairoMakie))
end

function _png_only!(cm::Module)
    others = filter(!=("image/png"), collect(cm.SUPPORTED_MIMES))
    cm.disable_mime!(others...)
    fig = cm.Figure()
    ok = showable(MIME("image/png"), fig) && !any(m -> showable(MIME(m), fig), others)
    ok || error("could not restrict CairoMakie to PNG output; the page would embed figures as HTML or SVG")
    return nothing
end

"""
    git_state(root) -> (commit, uncommitted)

HEAD, and the tracked files (other than the generated page and the notebook it
rewrites) that differ from it; `[\"unknown\"]` if git cannot tell.
"""
function git_state(root)
    git(args...) = readchomp(pipeline(Cmd(`git $(collect(args))`; dir=root); stderr=devnull))
    commit = try
        git("rev-parse", "HEAD")
    catch
        "unknown"
    end
    uncommitted = try
        out = git(
            "status",
            "--porcelain",
            "--untracked-files=no",
            "--",
            ".",
            ":(exclude)docs/src/generated",
            ":(exclude)notebooks/$NB_NAME.ipynb",
        )
        # "XY path" or "XY old -> new"; paths with spaces are quoted
        [strip(last(split(l[4:end], " -> ")), '"') for l in split(out, '\n') if length(l) > 3]
    catch
        ["unknown"]
    end
    return commit, String.(uncommitted)
end

"The sentence that replaces `RUN_INFO_MARK` at the top of the page."
function run_info_text(; generated, commit, uncommitted, quick, julia, threads, package_version)
    c = commit == "unknown" ? "an unknown commit" : "commit `$(first(commit, 10))`"
    if !isempty(uncommitted)
        files = length(uncommitted) <= 3 ? join(["`$f`" for f in uncommitted], ", ") : "$(length(uncommitted)) files"
        c *= " plus uncommitted changes to $files"
    end
    mode = quick ? "**quick mode** (demo-sized results, not for publication)" : "full mode"
    return "This page shows the outputs of one run of the notebook, in $mode, on $generated with " *
           "GeocarbPrecalibration $package_version at $c, Julia $julia and $threads threads, on " *
           "$(Sys.KERNEL == :NT ? "Windows" : string(Sys.KERNEL)). " *
           "Levels B and C of Part 2 depend on what that machine had installed (section 2.2 says what ran). " *
           "To run it yourself, download " *
           "[the notebook](https://github.com/TrevorLax/GEOCARBSULF/blob/main/notebooks/$NB_NAME.ipynb) " *
           "and follow *Setup*."
end

"""
    docs_page(; quick) -> String

Run every cell of tour.jl into the documentation page with its figures, write the
stamp, and rewrite the notebook without outputs. Returns the path of the page.
"""
function docs_page(; quick::Bool)
    root = REPO_ROOT
    before = TourStamp.current(root)
    commit, uncommitted = git_state(root)
    info = (;
        generated=Libc.strftime("%Y-%m-%d", time()),
        commit,
        uncommitted,
        quick,
        julia=string(VERSION),
        threads=Threads.nthreads(),
        package_version=string(TOML.parsefile(joinpath(root, "Project.toml"))["version"]),
    )
    Threads.nthreads() == 1 && @warn "Julia runs with one thread; start it with `-t auto` for a faster precalibration"

    png_only!()

    # Run in a scratch folder (Literate also makes it the working directory), and move
    # the page and its figures into docs/src/generated/ only if everything succeeded:
    # a failed run leaves the committed page untouched, and files the tour writes into
    # its working directory never reach the repository.
    stage = mktempdir()
    function postprocess(s)
        occursin(RUN_INFO_MARK, s) || error("$RUN_INFO_MARK not found in the `#md` note of tour.jl")
        occursin(r"EditURL = \"[^\"]*\"", s) || error("no EditURL in the generated page")
        s = replace(s, r"EditURL = \"[^\"]*\"" => "EditURL = \"$DOCS_EDIT_URL\"")   # relative to docs/src/generated
        return replace(s, RUN_INFO_MARK => run_info_text(; info...))
    end
    println("running every cell of tour.jl into the documentation page (", quick ? "quick" : "full", " mode)")
    page = withenv("GEOCARB_NOTEBOOK_FAST" => (quick ? "true" : "false")) do
        return Literate.markdown(
            NB_SRC,
            stage;
            name=DOCS_NAME,
            flavor=Literate.DocumenterFlavor(),
            execute=true,
            credit=false,
            image_formats=[(MIME("image/png"), ".png")],
            postprocess,
        )
    end
    println("home folder replaced by ~ in $(hide_home!(page)) place(s) of the page")

    text = read(page, String)
    occursin("data:image", text) && error("the page embeds an image as base64; figures must be separate PNG files")
    refs = [m[1] for m in eachmatch(r"!\[[^\]]*\]\(([^)\s]+)\)", text)]
    missing_refs = filter(r -> !isfile(joinpath(stage, r)), refs)
    isempty(missing_refs) || error("the page links figures that were not written: $(join(missing_refs, ", "))")
    fignum(f) = parse(Int, match(r"-(\d+)\.", f)[1])
    figures = sort(filter(f -> occursin(DOCS_FIGURE, f), readdir(stage)); by=fignum)
    isempty(figures) && error("the run produced no figures; check that CairoMakie displays figures as PNG")
    figures == sort(refs; by=fignum) || error("figure files and figure links of the page differ: $(figures) vs $(refs)")
    sizes = [f => filesize(joinpath(stage, f)) / 1024 for f in figures]
    println(length(figures), " figures, ", round(Int, sum(last, sizes; init=0.0)), " KB in total")
    big = filter(p -> last(p) > MAX_FIGURE_KB, sizes)
    isempty(big) || @warn "figures above $MAX_FIGURE_KB KB (the large-file limit of the pre-commit hook): " *
        join(["$(first(p)) ($(round(Int, last(p))) KB)" for p in big], ", ")

    after = TourStamp.current(root)
    after.page_sources == before.page_sources ||
        error("tour.jl or tour_helpers.jl changed during the run; run again so that the page matches them")
    after.package_inputs == before.package_inputs ||
        @warn "package files (src/, test/, ...) changed during the run; the stamp records them as at the start"

    mkpath(DOCS_GEN)
    for f in readdir(DOCS_GEN)   # the previous page and figures: none may be left behind
        (occursin(DOCS_FIGURE, f) || f == DOCS_NAME * ".md") && rm(joinpath(DOCS_GEN, f))
    end
    for f in vcat(figures, DOCS_NAME * ".md")
        cp(joinpath(stage, f), joinpath(DOCS_GEN, f))
    end
    page = joinpath(DOCS_GEN, DOCS_NAME * ".md")
    println("stamp: ", TourStamp.write_stamp(root, before; info...))
    println("notebook without outputs: ", plain_notebook())
    quick && @warn "quick mode: docs/make.jl rejects this page; run without --quick before committing"
    return page
end

function main(args)
    bad = filter(a -> !(a in OPTIONS), args)
    isempty(bad) || error("unknown option(s) $(join(bad, ", ")); valid: $(join(OPTIONS, ", "))")
    execute, hide, html = ("--execute" in args), ("--hide-home" in args), ("--html" in args)
    docs, quick = ("--docs-page" in args), ("--quick" in args)

    if docs || quick
        (docs && quick && length(args) == 2) ||
            (docs && length(args) == 1) ||
            error("--docs-page combines only with --quick, and --quick needs --docs-page")
        println("page: ", docs_page(; quick))
        return nothing
    end

    target = if execute
        Literate.notebook(NB_SRC, EXECUTED_DIR; name=NB_NAME, execute=true, credit=false)
    elseif hide || html
        joinpath(EXECUTED_DIR, NB_NAME * ".ipynb")   # work on the executed notebook already there
    else
        plain_notebook()
    end
    isfile(target) || error("$target does not exist; run with --execute first (or save an executed copy there)")
    println("notebook: ", target)

    if hide
        n = hide_home!(target)
        println("home folder replaced by ~ in $n place(s)")
    end
    if html
        println("html: ", to_html(target))
    end
    return nothing
end

# run as a script; notebooks/setup.jl includes this file and calls main itself
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
