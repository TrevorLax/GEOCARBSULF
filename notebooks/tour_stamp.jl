#!/usr/bin/env julia
#
# Staleness stamp of the executed "Notebook tour" page of the documentation.
#
# docs/src/generated/notebook_tour.md and its figures (notebook_tour-<n>.png) are
# produced on a developer's machine by a full run of notebooks/tour.jl and committed;
# the Docs workflow only renders them, it never runs the tour. To regenerate:
#
#   julia --project=notebooks -t auto notebooks/build.jl --docs-page
#
# That command also writes docs/src/generated/notebook_tour.stamp.toml, which records
# what the page was produced from:
#
#   page sources    notebooks/tour.jl and notebooks/tour_helpers.jl, file by file.
#                   If either changes, the page is stale and the check FAILS.
#   package inputs  the git-tracked files under src/, ext/, data/, experiments/ and
#                   test/, and Project.toml, as one hash. If they change, the check only
#                   WARNS: the page may show results of older code.
#
# Hashes are taken of the files as they are in the working tree. CRLF is normalised to
# LF so that a Windows and a Linux checkout give the same hash. Package inputs count
# only git-tracked files, so untracked local files (for example the stored R exports in
# test/legacy_comparison/output/) do not change the hash. The page sources are hashed
# directly, without git, so the failing part of the check never depends on git.
#
# Used by notebooks/build.jl (writes the stamp), docs/make.jl (checks it; a stale page
# fails the documentation build) and the prek pre-push hook `tour-page-stamp`:
#
#   julia --startup-file=no notebooks/tour_stamp.jl     # exit code 1 if the page is stale
#
# Needs only Base Julia and the SHA and TOML standard libraries (plus git for the
# package-input warning).

module TourStamp

using SHA: sha256
using TOML

const PAGE_SOURCES = ["notebooks/tour.jl", "notebooks/tour_helpers.jl"]
const PACKAGE_INPUTS = ["src", "ext", "data", "experiments", "test", "Project.toml"]
const PAGE = "docs/src/generated/notebook_tour.md"
const STAMP = "docs/src/generated/notebook_tour.stamp.toml"
const REGENERATE = "julia --project=notebooks -t auto notebooks/build.jl --docs-page"

"`bytes` with every CR LF pair replaced by LF."
function lf(bytes::Vector{UInt8})
    out = UInt8[]
    sizehint!(out, length(bytes))
    n = length(bytes)
    for i in 1:n
        (bytes[i] == 0x0d && i < n && bytes[i + 1] == 0x0a) || push!(out, bytes[i])
    end
    return out
end

"SHA-256 (hex) of the file `root/rel` after CR LF → LF, or `\"missing\"`."
function file_hash(root::AbstractString, rel::AbstractString)
    p = joinpath(root, split(rel, '/')...)
    return isfile(p) ? bytes2hex(sha256(lf(read(p)))) : "missing"
end

"One SHA-256 (hex) over the paths and contents of `files` (relative, `/`-separated)."
function combined_hash(root::AbstractString, files)
    io = IOBuffer()
    for f in sort(collect(files))
        print(io, f, '\0', file_hash(root, f), '\n')
    end
    return bytes2hex(sha256(take!(io)))
end

"Git-tracked files under `PACKAGE_INPUTS`, or `nothing` if git cannot list them."
function package_files(root::AbstractString)
    out = try
        read(pipeline(Cmd(`git ls-files -z -- $PACKAGE_INPUTS`; dir=root); stderr=devnull), String)
    catch
        return nothing
    end
    files = filter(!isempty, split(out, '\0'))
    return isempty(files) ? nothing : String.(files)
end

"""
    current(root) -> NamedTuple

Hashes of the page sources (a `Dict` path => hash) and of the package inputs (a
`String`, or `nothing` without git), with the number of package files hashed.
"""
function current(root::AbstractString)
    for f in PAGE_SOURCES
        isfile(joinpath(root, split(f, '/')...)) || error("$f not found under $root")
    end
    pkg = package_files(root)
    return (;
        page_sources=Dict(f => file_hash(root, f) for f in PAGE_SOURCES),
        package_inputs=(pkg === nothing ? nothing : combined_hash(root, pkg)),
        package_files=(pkg === nothing ? 0 : length(pkg)),
    )
end

"""
    write_stamp(root, hashes; run_info...)

Write `STAMP` from `hashes` (as returned by `current`, taken before the run) and the
details of the run (`generated`, `commit`, `uncommitted`, `quick`, `julia`, `threads`,
`package_version`).
"""
function write_stamp(root::AbstractString, hashes; run_info...)
    hashes.package_inputs === nothing &&
        error("git could not list the package inputs; the stamp needs git (run inside the repository checkout)")
    d = Dict{String,Any}(string(k) => v for (k, v) in run_info)
    d["page_sources"] = [Dict("path" => f, "sha256" => hashes.page_sources[f]) for f in PAGE_SOURCES]
    d["package_inputs"] = Dict("sha256" => hashes.package_inputs, "files" => hashes.package_files)
    path = joinpath(root, split(STAMP, '/')...)
    open(path, "w") do io
        println(io, "# Written by `notebooks/build.jl --docs-page`; checked by notebooks/tour_stamp.jl")
        println(io, "# (docs/make.jl and the pre-push hook tour-page-stamp). Do not edit by hand.")
        return TOML.print(io, d; sorted=true)
    end
    return path
end

"""
    check(root) -> (errors, warnings)

Compare the stamp with the files now. Errors: no page or stamp, a page made in quick
mode, or a changed page source. Warnings: changed package inputs, or no git.
"""
function check(root::AbstractString)
    errors, warnings = String[], String[]
    page, stamp = joinpath(root, split(PAGE, '/')...), joinpath(root, split(STAMP, '/')...)
    if !isfile(page) || !isfile(stamp)
        push!(errors, "the executed notebook-tour page ($PAGE) or its stamp is missing. Generate it with: $REGENERATE")
        return errors, warnings
    end
    s = try
        TOML.parsefile(stamp)
    catch e
        push!(errors, "$STAMP cannot be read ($(sprint(showerror, e))). Regenerate with: $REGENERATE")
        return errors, warnings
    end
    get(s, "quick", true) === false || push!(
        errors,
        "the notebook-tour page was generated in quick mode (demo-sized results). Regenerate in full mode: $REGENERATE",
    )
    cur = current(root)
    recorded = Dict(string(get(e, "path", "")) => string(get(e, "sha256", "")) for e in get(s, "page_sources", []))
    changed = [f for f in PAGE_SOURCES if get(recorded, f, "") != cur.page_sources[f]]
    isempty(changed) || push!(
        errors,
        "the notebook-tour page is out of date: $(join(changed, " and ")) changed since it was generated " *
        "(at commit $(first(string(get(s, "commit", "unknown")), 12))). Regenerate it with: $REGENERATE",
    )
    if cur.package_inputs === nothing
        push!(
            warnings,
            "git could not list the package inputs, so changes to src/, test/ etc. since the page " *
            "was generated were not checked",
        )
    elseif get(get(s, "package_inputs", Dict()), "sha256", "") != cur.package_inputs
        push!(
            warnings,
            "src/, ext/, data/, experiments/, test/ or Project.toml changed since the notebook-tour page " *
            "was generated " *
            "(at commit $(first(string(get(s, "commit", "unknown")), 12)), $(get(s, "generated", "unknown date"))); " *
            "its outputs may come from older code. Regenerate before a release: $REGENERATE",
        )
    end
    return errors, warnings
end

"Print `errors` and `warnings`, as GitHub annotations when run in GitHub Actions."
function report(errors, warnings; io::IO=stdout)
    gh = get(ENV, "GITHUB_ACTIONS", "") == "true"
    for (kind, msgs) in (("error", errors), ("warning", warnings)), m in msgs
        println(io, gh ? "::$kind file=$STAMP::$m" : "$(uppercase(kind)): $m")
    end
    isempty(errors) && isempty(warnings) && println(io, "notebook-tour page: up to date")
    return nothing
end

end # module TourStamp

if abspath(PROGRAM_FILE) == @__FILE__
    let root = normpath(joinpath(@__DIR__, ".."))
        errors, warnings = TourStamp.check(root)
        TourStamp.report(errors, warnings)
        exit(isempty(errors) ? 0 : 1)
    end
end
