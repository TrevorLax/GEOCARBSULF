#!/usr/bin/env julia
#
# Does the notebook tour run, from top to bottom, on this Julia version?
#
#   julia notebooks/test_notebook.jl            # quick mode (what CI runs)
#   julia +1.10 notebooks/test_notebook.jl      # the same on Julia 1.10 (juliaup)
#   julia notebooks/test_notebook.jl --full     # every cell at full size (15-30 min)
#   julia notebooks/test_notebook.jl --keep     # keep the scratch folder for inspection
#
# It works on a scratch copy of the repository, so it never touches this checkout and
# behaves like a fresh clone:
#
# 1. copies the repository (without .git, manifests, results and docs/build) to a
#    temporary folder; stored R exports in test/legacy_comparison/output are copied too
#    if they exist, so level B is exercised (only the export files, not figures or
#    .RData);
# 2. instantiates the package and notebook environments there with this Julia;
# 3. runs every cell of notebooks/tour.jl as a notebook (Literate.notebook with
#    execute = true: figures are rendered, as in Jupyter) and fails on the first error;
# 4. checks that notebooks/GeocarbPrecalibration_tour.ipynb is up to date with tour.jl
#    (same cells), if it exists.
#
# Quick mode sets GEOCARB_NOTEBOOK_FAST=true, which the notebook reads in its Settings
# cell: two test groups instead of all, fewer prior draws, a smaller precalibration.
# Level C runs only if R and a Fortran compiler are found, as in the notebook.
#
# On Julia 1.10, report the result in JULIA_110_STATUS in notebooks/tour_helpers.jl
# (:supported or :unsupported); the notebook warns 1.10 users accordingly.

const SRC = normpath(joinpath(@__DIR__, ".."))
const FULL = "--full" in ARGS
const KEEP = "--keep" in ARGS
const JULIA = Base.julia_cmd()

const SKIP_TOP = Set([".git", "results", "Manifest.toml", "logs"])
const SKIP_REL = Set([
    joinpath("docs", "build"),
    joinpath("docs", "Manifest.toml"),
    joinpath("docs", "src", "generated"),
    joinpath("notebooks", "Manifest.toml"),
    joinpath("notebooks", "executed"),
    joinpath("benchmark", "timing", "Manifest.toml"),
    joinpath("test", "legacy_comparison", "output"),
])

function copy_tree(src, dst, rel="")
    mkpath(dst)
    for name in readdir(src)
        r = isempty(rel) ? name : joinpath(rel, name)
        (isempty(rel) && name in SKIP_TOP) && continue
        r in SKIP_REL && continue
        s, d = joinpath(src, name), joinpath(dst, name)
        if isdir(s) && !islink(s)
            copy_tree(s, d, r)
        else
            cp(s, d; follow_symlinks=true)
        end
    end
end

function copy_exports(src_root, dst_root)
    from = joinpath(src_root, "test", "legacy_comparison", "output")
    isdir(from) || return 0
    to = mkpath(joinpath(dst_root, "test", "legacy_comparison", "output"))
    n = 0
    for f in readdir(from)
        keep = (startswith(f, "legacy_") && (endswith(f, ".csv") || endswith(f, ".txt"))) ||
            f in ("constants.csv", "time_series.csv")
        keep || continue
        cp(joinpath(from, f), joinpath(to, f))
        n += 1
    end
    return n
end

function step(title, cmd)
    println("\n== ", title)
    t = @elapsed ok = success(pipeline(cmd; stdout=stdout, stderr=stderr))
    println(ok ? "   ok" : "   FAILED", " (", round(Int, t), " s)")
    return ok
end

function main()
    work = mktempdir(; cleanup=!KEEP)
    repo = joinpath(work, "repo")
    println("Julia ", VERSION, " · ", FULL ? "full" : "quick", " mode · scratch copy: ", repo)
    copy_tree(SRC, repo)
    nexp = copy_exports(SRC, repo)
    println(nexp > 0 ? "copied $nexp stored R export files (level B will run)" : "no stored R exports (level B will be skipped)")
    nb = joinpath(repo, "notebooks")
    out = mkpath(joinpath(work, "out"))

    ok = step("instantiate the package environment", `$JULIA --project=$repo -e "using Pkg; Pkg.instantiate()"`)
    ok &= step(
        "instantiate the notebook environment",
        `$JULIA --project=$nb -e "using Pkg; Pkg.develop(PackageSpec(path=$(repr(repo)))); Pkg.instantiate()"`,
    )
    run_code = """
        using Literate
        Literate.notebook($(repr(joinpath(nb, "tour.jl"))), $(repr(out)); name="tour_executed", execute=true, credit=false)
        """
    cmd = addenv(`$JULIA --project=$nb -e $run_code`, "GEOCARB_NOTEBOOK_FAST" => FULL ? "false" : "true")
    ok = ok && step("run every cell of the notebook", cmd)

    committed = joinpath(SRC, "notebooks", "GeocarbPrecalibration_tour.ipynb")
    stale = false
    if isfile(committed)
        check_code = """
            using Literate, JSON
            fresh = Literate.notebook($(repr(joinpath(nb, "tour.jl"))), $(repr(out)); name="tour_fresh", execute=false, credit=false)
            cells(p) = [strip(join(c["source"])) for c in JSON.parsefile(p)["cells"]]
            a, b = cells($(repr(committed))), cells(fresh)
            if a == b
                println("   the committed notebook matches tour.jl")
            else
                i = something(findfirst(k -> k > length(a) || k > length(b) || a[k] != b[k], 1:max(length(a), length(b))), 0)
                println("   the committed notebook differs from tour.jl (first at cell ", i, "): run notebooks/build.jl and commit the result")
                exit(1)
            end
            """
        stale = !step("committed notebook up to date", `$JULIA --project=$nb -e $check_code`)
    else
        println("\n== committed notebook: notebooks/GeocarbPrecalibration_tour.ipynb not found; run notebooks/build.jl")
    end

    println()
    if ok && !stale
        println("PASS: the notebook runs on Julia ", VERSION)
    elseif ok
        println("PASS (runs) on Julia ", VERSION, ", but the committed .ipynb is out of date")
    else
        println("FAIL: the notebook does not run on Julia ", VERSION, " (see the output above)")
    end
    if VERSION < v"1.11"
        if ok
            println("Set JULIA_110_STATUS = :supported in notebooks/tour_helpers.jl.")
        else
            println(
                "Before setting JULIA_110_STATUS = :unsupported in notebooks/tour_helpers.jl, run this test on the newest ",
                "Julia too: if the same cell fails there, the problem is not specific to 1.10.",
            )
        end
    end
    KEEP && println("scratch folder kept: ", work)
    return ok && !stale ? 0 : 1
end

exit(main())
