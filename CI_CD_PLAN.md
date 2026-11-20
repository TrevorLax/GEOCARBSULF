# CI/CD plan for GeocarbPrecalibration.jl (GEOCARB_juliaed)

A self-contained summary of the pipeline built in November 2026, written so it can be set
up again on a new computer, or rebuilt from scratch. State as of **19 November 2026**,
including the follow-up pull request `ci/section-10-fixes`.

- Repository: <https://github.com/TrevorLax/GEOCARBSULF> (default branch `main`)
- Package: `GeocarbPrecalibration.jl`, a Julia port of the GEOCARBSULFvolc model and
  the Latin-hypercube precalibration of Wong et al. (2021). The original R/Fortran code
  is kept unmodified in `legacy/`.
- The canonical copy of every file named here is in the repository at `main`. The whole
  pipeline arrived in squash commit `260ba37` ("Origin/ci cd testing (#2)",
  13 November 2026).

---

## 1. Where things stand

**Done and merged in `main`:**
- every workflow, hook, script and config file listed below;
- the JuliaFormatter 2.x reformat;
- the docs-build hook fix (`scripts/dev/docs.jl`).

Dependabot PRs #3–#5 (compat bumps) were merged afterwards, and a `gh-pages` branch
exists, so Documenter has deployed at least once.

**Fixed by the follow-up pull request `ci/section-10-fixes`:**
- `.git-blame-ignore-revs` no longer lists `d994cb4` (a SHA from the squashed PR branch,
  never in `main`'s history). It now explains why the 2.x reformat can't be ignored
  (section 9.1);
- `CONTRIBUTING.md` and `.pre-commit-config.yaml` (header and `legacy-untouched`
  message) give the `SKIP` syntax for cmd, PowerShell and bash (section 6.4);
- `trailing-whitespace`, `end-of-file-fixer` and `check-added-large-files` run on
  commit only (section 9.4);
- this file replaces the older `CI_CD_PLAN.md`, whose status section still said "not
  committed".

**Still to do,** in priority order (details in section 10):
1. Check that the GitHub settings in section 7 are actually applied. I couldn't see
   repository settings or Actions run results from here.
2. Complete the JOSS and release items: placeholders, `AI_USAGE.md` TODOs, the paper,
   tagging `v0.1.0`, and Zenodo.

---

## 2. Requirements

1. Follow CI/CD best practices: least privilege, pinned dependencies, reproducible
   checks, fast feedback.
2. Meet every JOSS requirement: licence, `paper.md`/`paper.bib`, docs, tests, community
   files, AI-usage disclosure, archived release with a DOI.
3. Check results against the original R/Fortran code **before every push and every
   merge into `main`**. The live R/Fortran check is temporary; the golden Fortran
   fixtures are permanent.
4. Keep the documentation, `CHANGELOG.md` and the AI usage report up to date with every
   change, and check formatting before code is committed.

---

## 3. Decisions

| topic | decision |
|:--|:--|
| hook runner | **prek** 0.5.10, a Rust reimplementation of pre-commit. The config is a standard `.pre-commit-config.yaml` with no prek-only features, so `pre-commit` can run it too |
| formatter | **JuliaFormatter 2.14.11**, BlueStyle (`style = "blue"`, `margin = 120`), pinned exactly in `tools/format/` with a committed Manifest. The hook and the CI check use the same environment. BlueStyle 2.x defaults are kept, including `always_use_return` and `short_to_long_function_def` |
| Julia hook choice | a local `language: system` hook, not `qiaojunfeng/pre-commit-julia-format` or the official `julia-formatter`/`jlfmt` hooks. Those format with whatever version is installed globally, or require it, so they can drift from CI |
| tool versions | the newest JuliaFormatter, prek and zizmor, by decision. Everything else follows the rule "pin to a full SHA, at a release at least two weeks old" |
| legacy check before push | **always**: the pre-push hook runs the full live comparison on every push |
| legacy check in CI | **pinned toolchain**: `ubuntu-24.04` (fixes gfortran), R 4.6.1, CRAN packages from the Posit Package Manager snapshot dated 2026-11-10. `Weekly.yml` reruns it on the newest toolchain |
| changelog | **no escape labels**: every PR adds an entry to the top "(unreleased)" section of `CHANGELOG.md` |
| Dependabot | PRs opened by `dependabot[bot]` are **exempt by author** from the changelog and AI-disclosure rules; 14-day `cooldown` |
| releases | Zenodo archiving of tagged GitHub releases; no General registry, TagBot or CompatHelper |
| authorship | the port author is first and submitting author; Tony E. Wong is co-author; the original code (Wong & Cui) is credited in `CITATION.cff` and the paper |

---

## 4. Architecture

```text
 edit ──► git commit ──► git push ──► GitHub (push + PR checks) ──► merge to main ──► tag vX.Y.Z
          │ prek pre-commit           │ prek pre-push               │ ruleset: required checks   │ Release.yml
          │  hygiene, actionlint,     │  changelog/AI check,        │  up to date, linear        │  → GitHub release
          │  zizmor, JuliaFormatter,  │  golden tests, live R/      │                            │  → Zenodo DOI
          │  legacy/ guard            │  Fortran comparison, docs   │
```

### 4.1 Local hooks (`.pre-commit-config.yaml`; `fail_fast: true`)

The global `exclude` is `^(data/|test/fixtures/fortran/|test/legacy_comparison/output/|docs/build/)`.

| stage | hook | what it does |
|:--|:--|:--|
| commit | pre-commit-hooks v6.0.0 | `trailing-whitespace` (keeps markdown line breaks), `end-of-file-fixer`, `mixed-line-ending --fix=lf` (not `.bat`), `check-yaml`, `check-toml`, `check-merge-conflict`, `check-added-large-files --maxkb=1000`, `detect-private-key`. The fixers exclude `^legacy/` |
| commit | actionlint v1.7.12 | workflow lint (a Go hook; prek downloads Go if needed) |
| commit | zizmor v1.32.0 | workflow and Dependabot security audit |
| commit | `juliaformatter` | `julia --startup-file=no --project=tools/format scripts/dev/format.jl` on staged `.jl` files |
| commit | `legacy-untouched` | `language: fail` on any staged file under `legacy/` |
| push | `changelog-ai` | `julia --startup-file=no scripts/ci/check_changes.jl` (`always_run`) |
| push | `golden-regression` | `julia --project=. scripts/dev/test_group.jl regression` (`always_run`) |
| push | `legacy-comparison` | `julia --project=. test/legacy_comparison/run_comparison.jl --no-plots` (`always_run`, needs R) |
| push | `docs-build` | `julia --project=docs scripts/dev/docs.jl`, when `docs/src/`, `docs/make.jl`, `src/`, `AI_USAGE.md` or `README.md` changed |

Hooks are a convenience, not a guarantee: they're installed per clone, and
`--no-verify` skips them. The guarantee for `main` is the ruleset in section 7.

### 4.2 Workflows (`.github/workflows/`)

| workflow | trigger | required check | purpose |
|:--|:--|:--|:--|
| `CI.yml` | push, PR, `v*` tags | **CI result** | `Pkg.test()` on Ubuntu, macOS and Windows × Julia 1.10 and 1; a 4-thread job; a `pre` job allowed to fail; Codecov from one cell; one aggregate job gives a stable check name |
| `Legacy.yml` | push (all branches), PR, dispatch, `workflow_call` | **Legacy comparison** | the live R/Fortran comparison on the pinned toolchain, then the fixture-provenance check (section 5.3). Input `latest: true` switches to `ubuntu-latest`, the newest R release and the newest CRAN |
| `Docs.yml` | push, tags, PR | **Documentation** | docstring doctests, then `docs/make.jl` (strict, manual doctests, `checkdocs = :exports`); deploys to `gh-pages` with `GITHUB_TOKEN`; checkout without persisted credentials |
| `Format.yml` | push, PR | **Formatting** | `format("."; overwrite = false)` with `--project=tools/format` |
| `Metadata.yml` | push, PR | **Metadata** | `CITATION.cff` validation; the AI disclosure exists in `AI_USAGE.md`, the docs and the paper; `Project.toml` and `CITATION.cff` versions agree; TODO placeholders only warn |
| `Changes.yml` | PR (`opened`, `edited`, `synchronize`, `reopened`) | **Changelog and AI usage** | `scripts/ci/check_changes.jl` with `BASE_SHA`, `HEAD_SHA`, `PR_BODY` and `PR_AUTHOR` from the event, passed through `env:` only |
| `Lint.yml` | push, PR | **Lint** | `pipx install prek==0.5.10`, then `SKIP=juliaformatter,legacy-untouched prek run --all-files --show-diff-on-failure` |
| `Paper.yml` | changes to `paper/` or `AI_USAGE.md` | | JOSS paper PDF (Open Journals toolchain) |
| `Weekly.yml` | Mondays 06:00 UTC, dispatch | | tests on the newest dependencies; `Legacy.yml` with `latest: true`; docs link check; JET (advisory) |
| `Release.yml` | tag `vX.Y.Z` | | refuses if the versions disagree, the CHANGELOG section is missing or still "unreleased", or TODO/PORT_AUTHOR/OWNER placeholders remain; then publishes the GitHub release |

`Changes.yml`, `Format.yml` and `Lint.yml` run on `ubuntu-latest`. `Legacy.yml` stays
pinned to `ubuntu-24.04`.

---

## 5. Key mechanisms

### 5.1 One formatter environment
- `tools/format/Project.toml` sets `JuliaFormatter = "=2.14.11"` and `julia = "1.10"`.
  `tools/format/Manifest.toml` is committed (JuliaSyntax 1.0.2; made with Julia 1.12.5).
  `.gitignore` ignores only the root manifest (`/Manifest.toml`), along with
  `/docs/Manifest.toml` and `/benchmark/timing/Manifest.toml`.
- `scripts/dev/format.jl` instantiates on first use and calls `format(files)`. That
  honours `.JuliaFormatter.toml`, which `format_file` does not. It exits 1 if anything
  changed.
- To change the formatter version: do it in a commit of its own, followed by a
  reformat-only commit, then record that commit's SHA **as it appears on `main`** in
  `.git-blame-ignore-revs` (see section 9.1).

### 5.2 One tolerance file
`test/tolerances.toml` (`rtol_clean = 1e-8`, `rtol_post = 1e-4`, `atol = 1e-10`) is read
by `test/legacy_comparison/compare.jl` and `test/regression/test_fortran_golden.jl`,
both through `GeocarbPrecalibration.TOML` (the package loads the TOML stdlib, so the
tests need no extra dependency). Finite values must satisfy
`|a−b| ≤ atol + rtol·max(|a|,|b|)`, with `rtol_clean` before a run's first failed step
and `rtol_post` at or after it (finding F-08). Inf/NaN positions and % outbound must be
identical. The `--rtol-*` options of `run_comparison.jl` exist for experiments only;
CI and the hooks never pass them.

### 5.3 Matching the original R/Fortran
1. **Pre-push:** the golden `regression` group, then the full live comparison. On the
   Windows dev machine: about 15 s of R plus about 2 s of Julia comparison, plus
   start-up. 85 of 85 checks passed.
2. **`Legacy.yml`:**
   - installs gfortran and R 4.6.1, then `lhs`, `CholWishart` and `abind` from the dated
     P3M snapshot (`MASS` ships with R); the step fails if any package is missing;
   - compiles `legacy/fortran/src/*.f90` with `R CMD SHLIB` (done by `run_legacy.R`);
   - runs the original R driver (1000 samples plus six supplemental variants) and
     `run_comparison.jl`;
   - **fixture provenance:** `generate_fortran_fixtures.jl legacy/fortran ci 100`, then
     the `regression` group, which checks Julia against the committed `original`
     fixtures *and* the fresh Fortran `ci` ones. Fixtures regenerated from Julia would
     fail here;
   - writes the report to the job summary and uploads the output as an artifact.
3. **Permanent:** `test/regression` runs against `test/fixtures/fortran/original_*`,
   produced by the unmodified R/Fortran with Rtools 4.5 / gfortran 14.3 on Windows.

**Retiring the live check later:** delete `Legacy.yml`, the `legacy` job in
`Weekly.yml` and the `legacy-comparison` hook; remove **Legacy comparison** from the
required checks. Keep `test/regression`, `test/fixtures/fortran/` and
`test/tolerances.toml`.

### 5.4 Changelog and AI usage (`scripts/ci/check_changes.jl`)

The script uses only Base Julia and git, so it runs the same in the hook (Windows) and
in CI (Linux). It compares `HEAD_SHA` (default `HEAD`) with its merge base on
`BASE_SHA` (default `origin/main`; if neither exists it skips with exit 0). Problems are
printed as `::error`/`::warning` annotations on GitHub and as `ERROR:`/`WARNING:`
lines locally.

| # | rule | applies |
|:--|:--|:--|
| 1 | Any change needs added lines in the top `## ` section of `CHANGELOG.md`, and that heading must contain "unreleased". A release PR may change the heading itself instead. Lines added to older sections only warn | hook + CI |
| 2 | Changes to `test/tolerances.toml`, `test/fixtures/fortran/` or `legacy/` must be named in the added lines: "tolerance", "fixture", "legacy/" | hook + CI |
| 3 | Every AI tool in a `Co-Authored-By` trailer (pattern: anthropic, claude, openai, chatgpt, gpt, copilot, gemini, cursor, codeium, tabnine, aider) must appear in the *Tools* section of `AI_USAGE.md`; if AI was used, the entry must contain "AI" | hook + CI |
| 4 | `PR_BODY`: exactly one of the template boxes "No generative-AI tools…" / "AI tools were used…" is ticked, and "no AI" is refused when trailers name AI | CI |
| 5 | If the *Summary* section of `AI_USAGE.md` changes, `paper/paper.md` must change too | hook + CI |
| 6 | `src/model/` changed without `docs/src/model.md` or `docs/src/porting_notes.md`: warning only | hook + CI |
| — | `PR_AUTHOR == "dependabot[bot]"` skips rules 1, 3 (the changelog part) and 4 | CI |

It was tested on 25 scenarios covering every rule, with both outcomes, under Julia
1.9.4. To re-test: create throwaway git repos with `main` and a feature branch, set
`BASE_SHA=main`, and check the exit codes.

### 5.5 Workflow security baseline
- `permissions: contents: read` at the top of every workflow; jobs get more only where
  needed (CI cache pruning `actions: write`; Docs `contents`/`pull-requests`/`statuses:
  write`; Release `contents: write`). Each extra permission has a comment.
- Every action is pinned to a full SHA with a version comment. The hooks are pinned
  the same way.
- `persist-credentials: false` on every checkout, Docs included (Documenter pushes with
  `GITHUB_TOKEN`).
- Untrusted event text reaches scripts only through `env:`; no `pull_request_target`.
- Concurrency groups on every workflow (`Weekly` queues instead of cancelling);
  `timeout-minutes` on every job.
- Dependabot: GitHub Actions in one weekly group, Julia `[compat]` for `/` and `/docs`,
  `cooldown: default-days: 14`.
- zizmor is clean, including `--persona pedantic`. The one suppression is
  `# zizmor: ignore[self-repository]` on `uses: ./.github/workflows/Legacy.yml` in
  `Weekly.yml`, because actionlint 1.7.12 doesn't know the newer `$/` syntax zizmor
  suggests.

---

## 6. Setting up a new computer (Windows)

### 6.1 Install
| tool | version / note |
|:--|:--|
| Git for Windows | any recent version (`%(trailers:…)` log formats need git ≥ 2.24) |
| Julia | through `juliaup`; the dev machine used 1.12.5; the package needs ≥ 1.10 |
| R | **4.6.1** (matches CI), plus **Rtools 4.5**, so `R CMD SHLIB` can compile the legacy Fortran. The compiled `.dll`/`.o` files are git-ignored and are built on the first comparison run |
| uv | for installing prek (`uv tool install prek==0.5.10`); `pipx` also works |

Go and Python aren't needed: prek fetches toolchains for the actionlint and
pre-commit-hooks hooks.

### 6.2 Clone and set up
**Clone outside any synced folder** (OneDrive, Proton Drive, Google Drive). A sync client
once emptied the working copy, and it creates "name clash" copies; see section 9.2.

```bat
cd %USERPROFILE%\code
git clone git@github.com:TrevorLax/GEOCARBSULF.git GEOCARB_juliaed
cd GEOCARB_juliaed

julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=tools/format -e "using Pkg; Pkg.instantiate()"
rem the docs environment is set up by scripts/dev/docs.jl on the first docs build

uv tool install prek==0.5.10
prek install
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

### 6.3 First run and checks
```bat
set "SKIP=legacy-untouched"
prek run --all-files
set "SKIP="

julia --project=. -e "using Pkg; Pkg.test()"
julia --project=. test/legacy_comparison/run_comparison.jl --no-plots
julia --startup-file=no --project=docs scripts/dev/docs.jl
```
Expected results: the hooks pass (on a first run a fixer may change a file; run it
again); the tests pass; the legacy report ends with `SUMMARY: 84 of 84 comparisons
pass` (85 `@test`s); the docs build without errors.

### 6.4 Windows `cmd.exe` notes
- `SKIP=hook command` is bash syntax. In `cmd`, use `set "SKIP=hook-id"`, run the
  command, then `set "SKIP="`. In PowerShell:
  `$env:SKIP="hook-id"; prek run --all-files; Remove-Item Env:SKIP`. Always clear it.
- `run_tests.bat` writes time-stamped logs but **doesn't check exit codes**: it prints
  "Done" even after a failure. Read `logs\legacy_comparison_*.log` (look for
  `SUMMARY`) and `logs\test_suite_*.log`.

---

## 7. GitHub settings (verify on the website; I couldn't see them)

- [ ] **Actions:** default workflow permissions read-only; Actions may not create or
      approve PRs; approval required for workflows from outside contributors.
- [ ] **Security:** secret scanning with push protection, Dependabot alerts, private
      vulnerability reporting.
- [ ] **Ruleset on `main`:**
  - pull request required (0 approvals: you can't approve your own PR);
  - branches must be up to date before merging;
  - linear history; no force pushes or deletion; no bypass, or emergencies only;
  - required checks: **CI result**, **Legacy comparison**, **Documentation**,
    **Formatting**, **Metadata**, **Changelog and AI usage**, **Lint**.
- [ ] **Tag ruleset:** only you can create `v*` tags.
- [ ] **Pages:** served from the `gh-pages` branch (the branch exists).
- [ ] Secret `CODECOV_TOKEN`; Issues and Discussions enabled (the issue-template
      "Question" link points to Discussions).
- [ ] Zenodo GitHub integration turned on for the repository.

---

## 8. Day-to-day workflow

1. Create a branch from an up-to-date `main`.
2. Change code and tests, and add a CHANGELOG line under "(unreleased)". Name any
   tolerance, fixture or `legacy/` change; mention AI if it was used, and list the tool
   in `AI_USAGE.md`.
3. Commit. The pre-commit hooks format the code and lint it. If a hook changed files,
   review them, `git add` them and commit again.
4. Push. The pre-push hooks run the changelog check, the golden tests, the live
   comparison and, when relevant, the docs build.
5. Open the PR and tick exactly one AI box. All seven required checks must be green.
6. Merge with a **squash merge**, as PR #2 was. Read 9.1 before merging a reformat.

---

## 9. Lessons learned and known issues

1. **Squash merges throw away blame-ignore SHAs.** `.git-blame-ignore-revs` lists
   `d994cb4`, the 2.x reformat on the PR branch. Squashing replaced it with `260ba37`,
   which also holds all the CI work, so it can't be ignored without hiding real
   changes. **Fixed:** the dead SHA is gone, and a comment explains that the 2.x
   reformat is inside `260ba37`. **Rule for future reformats:** put the reformat
   in its own PR, squash-merge it, then add the **squash commit's SHA on `main`** in a
   follow-up PR. Squash merges and GitHub rebase merges both create new SHAs; only a
   merge commit keeps them, and the linear-history rule forbids merge commits.
2. **Synced folders.** The repo first lived in `Documents\code` under a sync client
   (Proton Drive, judging by the "name clash" file names). The working copy was found
   empty there, and the repo was then moved to `C:\Users\Albion\code\`. Keep git
   repositories out of synced folders.
3. **The docs environment broke after moving the folder.** `docs/Manifest.toml` is
   git-ignored and had recorded the old absolute path of the package. That was fixed by
   `scripts/dev/docs.jl`, which runs `Pkg.develop` and `Pkg.instantiate` before every
   build, just as `Docs.yml` does.
4. **Whitespace hooks ran on push too.** The pre-commit-hooks v6.0.0 manifest gives
   `trailing-whitespace`, `end-of-file-fixer` and `check-added-large-files`
   `stages: [pre-commit, pre-push, manual]`, which overrides `default_stages`. **Fixed:**
   the three hooks now set `stages: [pre-commit]` in `.pre-commit-config.yaml`.
5. **BlueStyle 2.x rewrites code,** not just layout: one-line definitions become
   `function … end` blocks, and a `return` is added before the last expression,
   including `return throw(…)` and `return` inside `do` blocks. A syntax-tree comparison
   with those rewrites undone found all 25 reformatted files equivalent. The result of
   `_pair` in `src/parameters/options.jl` is awkward but correct. The tests and the legacy
   comparison passed after the reformat. To get layout-only reformats, set
   `always_use_return = false` and `short_to_long_function_def = false` in
   `.JuliaFormatter.toml` (check the option names against the 2.x docs).
6. **Line endings.** The repo stores LF (`* text=auto eol=lf`); `*.bat` files are
   checked out as CRLF because `cmd.exe` can mishandle labels in LF-only batch files.
   `LICENSE` had CRLF in the working copy and was normalised by the hook.
7. **The changelog rule applies to every PR,** including CI-only and typo fixes.
   Group those under a "Maintenance" heading in the unreleased section.
8. **Hook output appears more than once.** prek runs hooks in batches, so a formatter
   message may print several times. A "Failed – files were modified" result from a fixer
   is expected: review the changes, re-stage and commit again.
9. **Verify on GitHub:** whether the P3M snapshot served the R packages, whether the
   Linux `ci` fixtures stayed within tolerance, and whether the docs deployed without
   persisted credentials. Merging PR #2 suggests the checks passed if the ruleset was
   enforced, but I couldn't see the Actions runs.

---

## 10. Remaining work

### Pipeline
- [x] Fix `.git-blame-ignore-revs` (9.1).
- [x] Add Windows `SKIP` syntax to `CONTRIBUTING.md`, the `.pre-commit-config.yaml`
      header and the `legacy-untouched` message (6.4).
- [x] Add `stages: [pre-commit]` to the three hygiene hooks (9.4).
- [x] Update the repository's own `CI_CD_PLAN.md` (replaced by this file).
- [ ] Optional: make `run_tests.bat` stop at the first failure and say which step failed.
- [ ] Verify the GitHub settings (section 7) and one green run of every required check.
- [ ] Open a test PR without a CHANGELOG entry and confirm **Changelog and AI usage**
      fails.

### JOSS and release
- [ ] Fill in the placeholders: `PORT_AUTHOR_NAME`/`PORT_AUTHOR_EMAIL` in `Project.toml`
      and `CODE_OF_CONDUCT.md`; the author TODOs (name, ORCID, affiliation) in
      `CITATION.cff`; `OWNER` in `README.md`, `CITATION.cff` and
      `.github/ISSUE_TEMPLATE/config.yml`.
- [ ] Complete `AI_USAGE.md`: tools and versions used for the original port,
      involvement per area, review process.
- [ ] Finish `paper/paper.md`: author block, *State of the field*, *Research impact
      statement*, *AI usage disclosure* (matching `AI_USAGE.md`), funding. Check the
      current JOSS guidelines, then download and proofread the PDF from `Paper.yml`.
- [ ] Release: mark `## 0.1.0` as released, make sure the `Project.toml` and
      `CITATION.cff` versions agree, and tag and push `v0.1.0`. Then add the Zenodo DOI to
      `CITATION.cff` and the README badge, and submit at <https://joss.theoj.org>.
- [ ] After acceptance: make the JOSS article the `preferred-citation`; add the badge.

### Later
- [ ] Move the R version and the P3M snapshot date forward on purpose, once
      `Weekly.yml` passes on the newer toolchain (with a CHANGELOG entry).
- [ ] Retire the live R/Fortran comparison when it's no longer needed (5.3).

---

## Appendix A: rebuilding from scratch

If you need to rebuild the pipeline in a new repository, apply it in this order, one
commit each, then reformat:

1. **Community and metadata:** `LICENSE` (GPL-3.0-or-later), `CITATION.cff`,
   `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `AI_USAGE.md`, `paper/`, issue forms and the
   PR template (two AI boxes, using the exact wording in 5.4).
2. **Tests:** `test/tolerances.toml`; `compare.jl` and `test_fortran_golden.jl` reading
   it; golden fixtures in `test/fixtures/fortran/`.
3. **Formatter:** `.JuliaFormatter.toml`, `tools/format/` (Project and Manifest),
   `scripts/dev/format.jl`.
4. **Hooks:** `.pre-commit-config.yaml`, `scripts/dev/test_group.jl`,
   `scripts/dev/docs.jl`, `scripts/ci/check_changes.jl`; `.gitattributes` with
   `*.bat text eol=crlf`; `.git-blame-ignore-revs`.
5. **Workflows:** the ten in section 4.2, plus `.github/dependabot.yml`.
6. **Reformat** with `prek run juliaformatter --all-files` in a PR of its own; run the
   tests and the legacy comparison; squash-merge; record the squash SHA (9.1).
7. **GitHub settings** (section 7), once each check has reported at least once. GitHub
   only offers checks it has seen when you pick required checks.

## Appendix B: small files, verbatim

`tools/format/Project.toml`
```toml
[deps]
JuliaFormatter = "98e50ef6-434e-11e9-1051-2b60c6c9e899"

[compat]
JuliaFormatter = "=2.14.11"
julia = "1.10"
```

`.JuliaFormatter.toml`
```toml
style = "blue"
margin = 120
```

`test/tolerances.toml`
```toml
rtol_clean = 1e-8   # before a run's first failed step
rtol_post = 1e-4    # at or after it (finding F-08)
atol = 1e-10
```

`.gitattributes`
```text
* text=auto eol=lf
*.csv text eol=lf
*.jld2 binary
*.dll binary
*.so binary
*.xlsx binary
*.bat text eol=crlf
```

`scripts/dev/format.jl` (the `juliaformatter` hook)
```julia
try
    using JuliaFormatter
catch
    using Pkg
    Pkg.instantiate()
    using JuliaFormatter
end
files = filter(f -> endswith(f, ".jl"), ARGS)
isempty(files) && exit(0)
# format() honours .JuliaFormatter.toml (format_file does not); true = nothing changed
if format(files)
    exit(0)
else
    println(stderr, "JuliaFormatter reformatted some files. Review the changes, `git add` them and commit again.")
    exit(1)
end
```

`scripts/dev/test_group.jl` (the `golden-regression` hook)
```julia
using Pkg
length(ARGS) == 1 || error("usage: test_group.jl GROUP")
Pkg.test(; test_args=ARGS)
```

`scripts/dev/docs.jl` (the `docs-build` hook)
```julia
using Pkg
Pkg.develop(PackageSpec(; path=normpath(joinpath(@__DIR__, "..", ".."))))
Pkg.instantiate()
include(joinpath(@__DIR__, "..", "..", "docs", "make.jl"))
```

Dependabot cooldown (in each `updates` entry of `.github/dependabot.yml`)
```yaml
    cooldown:
      default-days: 14
```

Pinned hook revisions (full commit SHAs)
```text
pre-commit/pre-commit-hooks   v6.0.0   3e8a8703264a2f4a69428a0aa4dcb512790b2c8c
rhysd/actionlint              v1.7.12  914e7df21a07ef503a81201c76d2b11c789d3fca
zizmorcore/zizmor-pre-commit  v1.32.0  06a39750ec31860bb44f2acf67182c40016cd1e7
```

The longer files are canonical in the repository: `.pre-commit-config.yaml`,
`scripts/ci/check_changes.jl` (236 lines after the reformat) and the ten workflows.
