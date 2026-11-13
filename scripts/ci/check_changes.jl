#!/usr/bin/env julia
#
# Checks that a branch records its changes as CONTRIBUTING.md requires:
#
#   1. every change adds an entry to the top, unreleased section of CHANGELOG.md;
#   2. changes to test/tolerances.toml, test/fixtures/fortran/ or legacy/ are named in that
#      entry (the words "tolerance", "fixture", "legacy/");
#   3. every AI tool named in a commit's Co-Authored-By trailer is listed in the Tools
#      table of AI_USAGE.md, and the CHANGELOG entry mentions "AI";
#   4. (pull requests) exactly one of the two AI boxes of the PR template is ticked,
#      and it agrees with the trailers;
#   5. if the Summary of AI_USAGE.md changes, paper/paper.md changes too;
#   6. (warning only) src/model/ changes without docs/src/model.md or
#      docs/src/porting_notes.md.
#
# Used by the prek pre-push hook `changelog-ai` and by .github/workflows/Changes.yml
# (required check "Changelog and AI usage"). Needs only Base Julia and git:
#
#   julia --startup-file=no scripts/ci/check_changes.jl
#
# Environment variables (all optional):
#   BASE_SHA   compare with this commit (default: origin/main)
#   HEAD_SHA   the branch tip (default: HEAD)
#   PR_BODY    pull-request description; enables rule 4
#   PR_AUTHOR  pull-request author. Pull requests opened by dependabot[bot] are exempt
#              from rules 1, 3 (CHANGELOG part) and 4, because Dependabot cannot
#              write a CHANGELOG entry or fill in the template.
#
# The branch is compared with its merge base, like the diff GitHub shows for a PR.

const IN_CI = get(ENV, "GITHUB_ACTIONS", "") == "true"
const ERRORS = String[]
const WARNINGS = String[]

function report(kind, msg; file="")
    if IN_CI
        loc = isempty(file) ? "" : " file=$file"
        println("::", kind, loc, "::", replace(msg, "\n" => "%0A"))
    else
        println(uppercase(kind), ": ", msg)
    end
end
err(msg; file="") = (push!(ERRORS, msg); report("error", msg; file))
warn(msg; file="") = (push!(WARNINGS, msg); report("warning", msg; file))

splitlines(s) = split(s, r"\r?\n")
git(args...) = readchomp(`git $(collect(args))`)
gitlines(args...) = filter(!isempty, splitlines(git(args...)))

"Contents of `path` at commit `rev`, or `nothing` if it does not exist there."
function show_file(rev, path)
    out = IOBuffer()
    ok = success(pipeline(`git show $rev:$path`; stdout=out, stderr=devnull))
    return ok ? String(take!(out)) : nothing
end

"Body of the markdown section `## heading` in `text`, or `nothing`."
function section(text, heading)
    text === nothing && return nothing
    lines = splitlines(text)
    i = findfirst(l -> startswith(l, "## ") && strip(l[4:end]) == heading, lines)
    i === nothing && return nothing
    j = findnext(l -> startswith(l, "## "), lines, i + 1)
    return join(lines[(i + 1):(j === nothing ? end : j - 1)], "\n")
end

"Lines added to `path` between `base` and `head`, with their line numbers in `head`."
function added_lines(base, head, path)
    out = Tuple{Int,String}[]
    n = 0
    for l in splitlines(git("diff", "-U0", "--no-color", base, head, "--", path))
        m = match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", l)
        if m !== nothing
            n = parse(Int, m.captures[1])
        elseif startswith(l, "+") && !startswith(l, "+++")
            push!(out, (n, String(l[2:end])))
            n += 1
        end
    end
    return out
end

# Co-Authored-By trailers that name an AI tool. Matched case-insensitively against the
# whole trailer, e.g. "Claude Opus 5.5 <noreply@anthropic.com>".
const AI_TRAILER = r"anthropic|claude|openai|chatgpt|\bgpt|copilot|gemini|cursor|codeium|tabnine|aider"i

function main()
    head = get(ENV, "HEAD_SHA", "HEAD")
    base = get(ENV, "BASE_SHA", "")
    if isempty(base)
        if !success(pipeline(`git rev-parse --verify --quiet origin/main`; stdout=devnull))
            println("check_changes: no origin/main to compare with; nothing checked")
            return 0
        end
        base = "origin/main"
    end
    mb = git("merge-base", base, head)
    changed = gitlines("diff", "--name-only", mb, head)
    if isempty(changed)
        println("check_changes: no changes against $base")
        return 0
    end
    println("check_changes: $(length(changed)) changed file(s) against $base (merge base $(first(mb, 12)))")
    exempt = get(ENV, "PR_AUTHOR", "") == "dependabot[bot]"
    exempt && println("check_changes: pull request by dependabot[bot]; CHANGELOG and AI-disclosure rules skipped")

    # 1. CHANGELOG entry in the top, unreleased section
    entry = ""
    if "CHANGELOG.md" in changed
        text = show_file(head, "CHANGELOG.md")
        lines = text === nothing ? SubString{String}[] : splitlines(text)
        heads = findall(l -> startswith(l, "## "), lines)
        if isempty(heads)
            err("CHANGELOG.md has no '## ' section."; file="CHANGELOG.md")
        else
            h1 = heads[1]
            h2 = length(heads) > 1 ? heads[2] : length(lines) + 1
            added = added_lines(mb, head, "CHANGELOG.md")
            releasing = any(n == h1 for (n, _) in added)   # the top heading itself changed
            if !occursin("unreleased", lowercase(lines[h1])) && !releasing
                err(
                    "The top section of CHANGELOG.md ('$(lines[h1])') is not marked unreleased. " *
                    "Start a new '## X.Y.Z (unreleased)' section for this change.";
                    file="CHANGELOG.md",
                )
            end
            for (n, t) in added
                if !isempty(strip(t)) && !(h1 <= n < h2)
                    warn(
                        "CHANGELOG.md line $n was added outside the top section; entries for this change " *
                        "belong in the unreleased section.";
                        file="CHANGELOG.md",
                    )
                end
            end
            entry = join((t for (n, t) in added if h1 < n < h2 && !isempty(strip(t))), "\n")
            if isempty(entry) && !releasing && !exempt
                err(
                    "CHANGELOG.md changed, but no line was added to its top section ('$(lines[h1])'). " *
                    "Describe this change there.";
                    file="CHANGELOG.md",
                )
            end
        end
    elseif !exempt
        err(
            "CHANGELOG.md has no entry for this change. Every change needs one, in the top " *
            "'(unreleased)' section (see CONTRIBUTING.md).";
            file="CHANGELOG.md",
        )
    end

    # 2. special changes must be named in the entry
    special = (
        ("test/tolerances.toml", f -> f == "test/tolerances.toml", r"tolerance"i, "tolerance"),
        ("test/fixtures/fortran/", f -> startswith(f, "test/fixtures/fortran/"), r"fixture"i, "fixture"),
        ("legacy/", f -> startswith(f, "legacy/"), r"legacy/", "legacy/"),
    )
    for (what, touches, re, word) in special
        if any(touches, changed) && !occursin(re, entry)
            err(
                "This change touches $what. Its CHANGELOG entry must say so (use the word \"$word\") " *
                "and explain why.";
                file="CHANGELOG.md",
            )
        end
    end

    # 3. AI tools named in commit trailers are listed in AI_USAGE.md
    trailers = gitlines("log", "--format=%(trailers:key=Co-authored-by,valueonly,separator=%x0A)", "$mb..$head")
    ai_trailers = unique(filter(t -> occursin(AI_TRAILER, t), String.(strip.(trailers))))
    tools = section(show_file(head, "AI_USAGE.md"), "Tools")
    for t in ai_trailers
        name = strip(replace(t, r"<[^>]*>" => ""))
        if tools === nothing || !occursin(lowercase(name), lowercase(tools))
            err(
                "A commit has the trailer 'Co-Authored-By: $t', but '$name' is not listed in the " *
                "Tools table of AI_USAGE.md.";
                file="AI_USAGE.md",
            )
        end
    end
    ai_used = !isempty(ai_trailers)

    # 4. the PR template's AI boxes
    body = get(ENV, "PR_BODY", nothing)
    if body !== nothing && !exempt
        no_ai = occursin(r"^\s*[-*]\s*\[[xX]\]\s*No generative-AI tools"m, body)
        yes_ai = occursin(r"^\s*[-*]\s*\[[xX]\]\s*AI tools were used"m, body)
        if no_ai == yes_ai
            err("Tick exactly one of the two boxes under 'AI usage' in the pull-request description.")
        elseif ai_used && no_ai
            err(
                "Commits carry AI Co-Authored-By trailers ($(join(ai_trailers, "; "))), but the " *
                "pull request says no AI tools were used.",
            )
        end
        ai_used |= yes_ai
    end
    if ai_used && !exempt && !occursin(r"\bAI\b", entry)
        err(
            "AI tools were used for this change; say so in its CHANGELOG entry (for example " *
            "\"drafted with an AI coding assistant, see AI_USAGE.md\").";
            file="CHANGELOG.md",
        )
    end

    # 5. AI_USAGE.md summary and the paper's disclosure stay in step
    old = section(show_file(mb, "AI_USAGE.md"), "Summary")
    new = section(show_file(head, "AI_USAGE.md"), "Summary")
    if old !== nothing && new !== nothing && strip(old) != strip(new) && !("paper/paper.md" in changed)
        err(
            "The Summary of AI_USAGE.md changed but paper/paper.md did not. Update the paper's " *
            "'AI usage disclosure' section to match.";
            file="paper/paper.md",
        )
    end

    # 6. model documentation (advisory)
    if any(f -> startswith(f, "src/model/"), changed) &&
        !any(in(changed), ("docs/src/model.md", "docs/src/porting_notes.md"))
        warn(
            "src/model/ changed but docs/src/model.md and docs/src/porting_notes.md did not. " *
            "Check whether the model documentation needs updating.",
        )
    end

    if isempty(ERRORS)
        println("check_changes: OK", isempty(WARNINGS) ? "" : " ($(length(WARNINGS)) warning(s))")
        return 0
    end
    println("check_changes: $(length(ERRORS)) problem(s), see above")
    return 1
end

exit(main())
