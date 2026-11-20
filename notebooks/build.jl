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
# --html needs Jupyter's nbconvert: the program named by the JUPYTER environment
# variable, else `jupyter` on the PATH, else the private Jupyter that IJulia installs
# (`using IJulia; jupyterlab()` offers to install it).
#
# The "Publish notebook" workflow (.github/workflows/PublishNotebook.yml) runs
# `--execute --hide-home --html` on a release tag with Julia 1.12.5, R and gfortran
# installed so that level C runs. Release.yml calls it before creating the release and
# attaches the .ipynb and the .html to the release before publishing it.

using Literate

const NB_DIR = @__DIR__
const NB_NAME = "GeocarbPrecalibration_tour"
const NB_SRC = joinpath(NB_DIR, "tour.jl")
const EXECUTED_DIR = joinpath(NB_DIR, "executed")
const OPTIONS = ("--execute", "--hide-home", "--html")

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

function main(args)
    bad = filter(a -> !(a in OPTIONS), args)
    isempty(bad) || error("unknown option(s) $(join(bad, ", ")); valid: $(join(OPTIONS, ", "))")
    execute, hide, html = ("--execute" in args), ("--hide-home" in args), ("--html" in args)

    target = if execute
        Literate.notebook(NB_SRC, EXECUTED_DIR; name=NB_NAME, execute=true, credit=false)
    elseif hide || html
        joinpath(EXECUTED_DIR, NB_NAME * ".ipynb")   # work on the executed notebook already there
    else
        Literate.notebook(NB_SRC, NB_DIR; name=NB_NAME, execute=false, credit=false)
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
abspath(PROGRAM_FILE) == @__FILE__ && main(ARGS)
