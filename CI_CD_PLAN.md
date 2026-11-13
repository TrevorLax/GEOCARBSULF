# CI/CD plan for GeocarbPrecalibration.jl

This plan sets up continuous integration and delivery for publishing the package on
GitHub (<https://github.com/TrevorLax/GEOCARBSULF>) and submitting it to the Journal
of Open Source Software (JOSS). It has four requirements:

1. Follow CI/CD best practices.
2. Meet every JOSS requirement.
3. Check results against the original R/Fortran code before every push and every merge
   into `main`. The live R/Fortran check is temporary and will be dropped later; the
   golden Fortran fixtures stay.
4. Make sure documentation, `CHANGELOG.md` and the AI usage report are updated with
   every change, and that formatting is checked before code is committed.

**Status (12 November 2026):**
- *Done earlier, staged, not committed:* the eight original workflows, Dependabot,
  issue and PR templates, `AI_USAGE.md`, `CODE_OF_CONDUCT.md`, `paper/`, and a BlueStyle
  reformat with JuliaFormatter 1.x. Locally the test suite passed (460 tests), the live
  R/Fortran comparison passed (85 checks), the docs built strictly with doctests.
- *Implemented on 12 November, not committed (unstaged, on top of the staged work):*
  - `.pre-commit-config.yaml` (prek), `scripts/dev/format.jl`, `scripts/dev/test_group.jl`;
  - `tools/format/Project.toml` (JuliaFormatter `=2.14.11`) and `Format.yml` using it;
  - `test/tolerances.toml`, read by `compare.jl` and `test_fortran_golden.jl`;
  - `scripts/ci/check_changes.jl`, `Changes.yml` and `Lint.yml`;
  - pinned `Legacy.yml` with the fixture check, `Weekly.yml` calling it with
    `latest: true`;
  - Dependabot cooldown, `persist-credentials: false` in `Docs.yml`, `*.bat` checked out
    with CRLF, `.git-blame-ignore-revs` (empty), and updated `CONTRIBUTING.md`,
    `docs/src/testing.md`, PR template, `CHANGELOG.md` and `AI_USAGE.md`.
- *Checked so far:* `actionlint` 1.7.12 clean; `zizmor` 1.32.0 clean, including the
  pedantic persona; the commit-stage hooks (except Julia ones and actionlint-via-prek)
  run with prek 0.5.10 on a copy of the repo; `check_changes.jl` passes 25 scenario
  tests (every rule, both outcomes) under Julia 1.9.
- *Not yet run anywhere:* the JuliaFormatter 2.x reformat, the test suite and the live
  comparison after these changes, the docs build, and every workflow on GitHub. These
  need Julia ≥ 1.10 and R (your machine) or GitHub.

## Decisions

| topic | decision |
|:--|:--|
| authorship | port author first and submitting author; Tony E. Wong co-author |
| releases | Zenodo archiving only; no General registry, TagBot or CompatHelper |
| hook runner | **prek** (<https://github.com/j178/prek>). The config is a standard `.pre-commit-config.yaml` with no prek-only features (no `repo: builtin`), so `pre-commit` can run it too |
| formatter | **JuliaFormatter 2.x**, exact version (2.14.11) pinned in `tools/format/Project.toml`. The pre-commit hook and `Format.yml` both use that environment, so they cannot drift apart |
| tool versions | the newest releases of JuliaFormatter (2.14.11), prek (0.5.10) and zizmor (1.32.0), by decision, although they are younger than the two-week rule. Other pins follow the rule |
| legacy check before push | **always**: the prek `pre-push` hook runs the full live comparison on every push, whatever files changed |
| required legacy check in CI | **pinned**: `ubuntu-24.04` (which fixes gfortran), R 4.6.1 (the version used locally), CRAN packages from a dated Posit Package Manager snapshot. `Weekly.yml` keeps testing the newest R and packages |
| changelog | **no escape labels**: every pull request must add an entry to the unreleased section of `CHANGELOG.md` |
| Dependabot PRs | **exempt by author**: pull requests opened by `dependabot[bot]` skip the CHANGELOG and AI-disclosure rules |

## Overview

| workflow | runs on | required check | purpose |
|:--|:--|:--|:--|
| `CI.yml` | push, PR | **CI result** | test suite on Linux/macOS/Windows; includes the Fortran golden fixtures |
| `Legacy.yml` (**changed**) | push (all branches), PR | **Legacy comparison** | live comparison with the unmodified R/Fortran code on a pinned toolchain; also checks that the committed fixtures match the Fortran (temporary) |
| `Docs.yml` (**changed**) | push, tags, PR | **Documentation** | Documenter.jl build with jldoctests and `checkdocs = :exports`; deploys to GitHub Pages with `GITHUB_TOKEN`, without persisted checkout credentials |
| `Format.yml` (**changed**) | push, PR | **Formatting** | BlueStyle check with the JuliaFormatter 2.x pinned in `tools/format` |
| `Metadata.yml` | push, PR | **Metadata** | `CITATION.cff` validity, AI usage disclosure present, versions agree; warns about TODO placeholders |
| `Changes.yml` (**new**) | PR | **Changelog and AI usage** | CHANGELOG entry, AI disclosure and trailers, special changes named (see below) |
| `Lint.yml` (**new**) | push, PR | **Lint** | the commit-stage hooks on all files with prek: file hygiene, `actionlint`, `zizmor` |
| `Paper.yml` | changes to `paper/` or `AI_USAGE.md` | | JOSS paper PDF |
| `Weekly.yml` (**changed**) | Mondays 06:00 UTC | | tests with the newest dependencies, `Legacy.yml` with `latest: true` (newest R, CRAN, runner image), link check, JET |
| `Release.yml` | tag `vX.Y.Z` | | checks metadata and placeholders, then publishes a GitHub release (Zenodo archives it) |

Supporting files:
- `.github/dependabot.yml`;
- issue forms and a pull-request template in `.github/`;
- `CODE_OF_CONDUCT.md`, `AI_USAGE.md`, `paper/paper.md` and `paper/paper.bib`;
- **new:** `.pre-commit-config.yaml`, `tools/format/`, `scripts/dev/`,
  `scripts/ci/check_changes.jl`, `test/tolerances.toml`, `.git-blame-ignore-revs`;
- **changed:** `.gitattributes` (`*.bat text eol=crlf`).

## Requirement 1: best practices

- **Least privilege.** Every workflow defaults to `permissions: contents: read`. Jobs
  get more only where they need it:
  - CI tests: `actions: write`, for cache pruning;
  - Docs: `contents`, `pull-requests` and `statuses: write`;
  - Release: `contents: write`.

  Checkouts use `persist-credentials: false`, except in Docs, which deploys.
- **Pinned actions and hooks.** Every third-party action and every hook repository is
  pinned to a full commit SHA, with a version comment, at a release at least two weeks
  old (exception by decision: JuliaFormatter, prek and zizmor use their newest
  releases). Dependabot bumps the actions weekly as one grouped PR, and also bumps
  `[compat]` entries for `/` and `/docs`; a 14-day `cooldown` makes it follow the
  two-week rule. Hook revisions are bumped by hand with `prek auto-update` and
  reviewed like any other change.
- **Untrusted input.** No workflow writes `${{ github.event.* }}` text (PR titles,
  bodies, branch names) into a `run:` script. `Changes.yml` reads the PR body from an
  environment variable. No workflow uses `pull_request_target`.
- **Concurrency and timeouts.** A newer push cancels superseded runs on non-`main`
  refs. Every job has a `timeout-minutes`.
- **Test matrix.**
  - Julia 1.10 (the LTS and the `[compat]` floor) and Julia 1, on Ubuntu, macOS and
    Windows.
  - A 4-thread job, which checks that results are deterministic across thread counts.
  - A `pre` job for the next Julia release, allowed to fail.

  A single aggregate job, **CI result**, gives branch protection one stable check name.
- **Coverage.** Uploaded to Codecov from one matrix cell only.
- **Caching.** `julia-actions/cache` for the Julia depot; P3M binaries for R packages.
- **Drift detection.** `Weekly.yml` runs everything against the newest dependencies, R
  packages and gfortran, plus an external link check of the docs and JET static
  analysis (advisory). This catches breakage even when nobody pushes, and is the only
  place the unpinned toolchain is tested.
- **Workflow security.** `Lint.yml` runs `actionlint` and `zizmor` (with the other
  commit hooks) on every change, at the same pinned versions as the local hooks.
  `zizmor`'s one suppressed finding is its suggestion of the new `$/` self-repository
  syntax in `Weekly.yml`, kept as `./` because `actionlint` 1.7.12 does not know it.
- **Manual reruns.** Every workflow has `workflow_dispatch`.

### Formatting (changed)

- `tools/format/Project.toml` holds JuliaFormatter with an exact compat bound
  (`JuliaFormatter = "=2.14.11"`).
  `tools/format/Manifest.toml` is committed so that the formatter's own dependencies
  (JuliaSyntax and others) are fixed too; `.gitignore` only ignores the root manifest.
- `.JuliaFormatter.toml` stays `style = "blue"`, `margin = 120`.
- `Format.yml` instantiates `tools/format` instead of adding "JuliaFormatter 1", then
  runs `format("."; overwrite = false)` as now.
- The pre-commit hook runs `scripts/dev/format.jl` in the same environment. The script
  calls `format(files)` (not `format_file`), so `.JuliaFormatter.toml` is honoured, and
  exits 1 if it changed anything.
- Moving from 1.x to 2.x reformats the codebase once. That is its own commit: it must
  change layout only, and the full test suite and the live comparison must pass on it
  unchanged. Its SHA, and the SHA of the earlier 1.x reformat, go in
  `.git-blame-ignore-revs` so GitHub's blame view skips them.

### Local hooks with prek (new)

Install once per clone: `prek install` (installs the `pre-commit` and `pre-push` hooks
listed in `default_install_hook_types`). Then `SKIP=legacy-untouched prek run
--all-files` once. The configuration is in `.pre-commit-config.yaml`; `fail_fast` is on.

| stage | hook | what |
|:--|:--|:--|
| commit | pre-commit-hooks 6.0.0 | trailing whitespace, end of file, LF line endings (not `.bat`), YAML, TOML, merge conflicts, files over 1 MB, private keys. The fixers skip `legacy/` |
| commit | actionlint 1.7.12, zizmor 1.32.0 | workflow lint and security |
| commit | `juliaformatter` | `julia --project=tools/format scripts/dev/format.jl` on staged `.jl` files |
| commit | `legacy-untouched` | `language: fail` on any staged file in `legacy/` |
| push | `changelog-ai` | `scripts/ci/check_changes.jl` against `origin/main` |
| push | `golden-regression` | `scripts/dev/test_group.jl regression` |
| push | `legacy-comparison` | `run_comparison.jl --no-plots`, `always_run` |
| push | `docs-build` | `docs/make.jl`, when `docs/`, `src/`, `AI_USAGE.md` or `README.md` changed |

Data, the golden fixtures in `test/fixtures/fortran/`, comparison output and
`docs/build/` are excluded from every hook.

Notes:
- Julia hooks use `language: system` with the code in script files. That avoids
  Windows quoting problems and does not depend on prek's support for `language: julia`.
- `actionlint`'s hook is a Go hook; prek downloads a Go toolchain the first time if
  none is installed.
- The legacy comparison needs R on the `PATH` (or `RSCRIPT`), as described in
  `test/legacy_comparison/README.md`. On the development machine the R run took about
  15 s and the Julia comparison about 2 s (log of 30 October), plus Julia start-up.
- To change `legacy/` on purpose: `SKIP=legacy-untouched git commit ...`, plus a
  CHANGELOG entry that names `legacy/` (enforced in CI).
- Hooks are a convenience, not a guarantee: they are installed per clone and
  `--no-verify` skips them. The guarantee for `main` is the branch ruleset and the
  required checks.

## Requirement 2: JOSS requirements

| JOSS requirement | how it is met |
|:--|:--|
| OSI-approved licence | GPL-3.0-or-later (`LICENSE`); the original code keeps `legacy/LICENSE.txt` |
| Submitting author is a major contributor | port author first, Tony E. Wong second, in `paper/paper.md`, `CITATION.cff` and `Project.toml`. The original R/Fortran code (Wong & Cui) is credited under `references` in `CITATION.cff` and in the paper |
| `paper.md` + `paper.bib` | `paper/` has these sections: Summary, Statement of need, State of the field, Software design, Research impact statement, AI usage disclosure, Acknowledgements, References. All bibliography DOIs were checked against doi.org. `Paper.yml` builds the PDF with the Open Journals toolchain |
| Statement of need | in the README, the docs home page and the paper |
| Installation instructions | README: `Pkg.add(url = ...)` (the package is not registered) or clone and instantiate; requires Julia ≥ 1.10 |
| Example usage | README example and the docs quick start. The quick start is a `jldoctest`, so CI checks it |
| API documentation | Documenter.jl site with doctests on the docstrings of `run_geocarb`, `ConstantParams` and `TimeForcings` and on the manual pages. Broken references, doctests and undocumented exports fail the build. Deployed to GitHub Pages (dev from `main`, stable from tags, previews for PRs) |
| Automated tests | the test suite in CI on three operating systems, plus the doctests group and the live legacy comparison |
| Community guidelines | `CONTRIBUTING.md` covers reporting bugs, getting help, pull requests and AI-assisted contributions. Also `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), issue forms and a PR template |
| AI usage disclosure | `AI_USAGE.md` is the single source. It is generated into the "AI usage" docs page and summarised in the paper's *AI usage disclosure* section. `Metadata.yml` fails if any of the three is missing; `Changes.yml` keeps them current |
| Archived release with DOI | `Release.yml` publishes a release when a version tag is pushed, and Zenodo archives it. The release is refused if the versions disagree, the CHANGELOG section is missing or still marked "unreleased", or any TODO/author/owner placeholders remain |
| Citation metadata | `CITATION.cff`, validated by `Metadata.yml` and checked to match the `Project.toml` version |

## Requirement 3: matching the original R/Fortran results

There are three layers of protection:

1. **Before every push (local, new).** The prek `pre-push` hook runs the golden
   regression group and the full live comparison. A failure stops the push.
2. **Live comparison in CI (`Legacy.yml`, temporary).** It runs on every push to any
   branch and on every PR, and it is a required check, so nothing reaches `main`
   without it. On `ubuntu-24.04` it:
   - installs R 4.6.1 (`r-lib/actions/setup-r` with `r-version: "4.6.1"`) and installs
     `lhs`, `CholWishart` and `abind` from the dated snapshot
     `https://packagemanager.posit.co/cran/__linux__/noble/2026-11-10` (`MASS` ships
     with R); the step fails if any package is missing. Change the date only on
     purpose, with a CHANGELOG entry;
   - compiles the unmodified Fortran in `legacy/` with `R CMD SHLIB` and the image's
     gfortran;
   - runs the original R driver on 1000 prior samples and six supplemental variants;
   - runs `test/legacy_comparison/run_comparison.jl`;
   - **new:** regenerates golden fixtures (label `ci`, 100 draws plus edge cases) with
     the libraries R just compiled, using `test/fixtures/generate_fortran_fixtures.jl`,
     and runs the `regression` group, which then checks Julia against both the
     committed `original` fixtures and the fresh `ci` ones. If the committed fixtures
     were ever regenerated from Julia, a model change would pass on them but fail on
     the fresh Fortran output.

   Julia must reproduce CO2, O2 and temperature at every step within `rtol = 1e-8`, or
   `1e-4` after a run's first failed step, with `atol = 1e-10`. Inf/NaN positions must
   be identical and % outbound must be equal. Any mismatch fails the job. The report
   goes to the job summary, and the full output is uploaded as an artifact.
3. **Golden-master fixtures (`test/regression`, permanent).** These are outputs of the
   compiled Fortran stored in `test/fixtures/fortran/`. They are checked by `CI.yml` on
   every operating system and Julia version, without R.

### One place for the tolerances (new)

Today the same numbers are written twice: `const RTOL_CLEAN/RTOL_POST/ATOL` in
`test/legacy_comparison/compare.jl` and a literal tuple in
`test/regression/test_fortran_golden.jl`. Both will read `test/tolerances.toml`:

```toml
rtol_clean = 1e-8   # before a run's first failed step
rtol_post  = 1e-4   # at or after it (finding F-08)
atol       = 1e-10
```

The `--rtol-clean`, `--rtol-post` and `--atol` options of `run_comparison.jl` stay
for experiments, but `Legacy.yml` and the pre-push hook never pass them, so CI always
uses the file.

**Dropping the live comparison later:**
1. Delete `.github/workflows/Legacy.yml`, the `legacy` job in `Weekly.yml` and the
   `legacy-comparison` hook.
2. Remove **Legacy comparison** from the required checks on `main`.
3. Keep `test/regression`, `test/fixtures/fortran/` and `test/tolerances.toml`. They
   continue to pin results to the Fortran. `legacy/` and `test/legacy_comparison/`
   can stay so the comparison can still be run by hand.

The same steps are in `docs/src/testing.md`.

## Requirement 4: documentation, changelog and AI usage (new)

`scripts/ci/check_changes.jl` uses only Julia and git, so it runs the same way in
the pre-push hook (Windows) and in `Changes.yml` (Linux). It compares the branch with
its merge base on `main`. In CI the base and head SHAs and the PR body come from
environment variables.

| rule | check | where |
|:--|:--|:--|
| changelog | any change at all requires added lines in `CHANGELOG.md`, inside the top `## ` section, whose heading contains "unreleased". A release PR may instead change that heading itself. Lines added to older sections give a warning | hook + CI |
| Dependabot | pull requests opened by `dependabot[bot]` skip the changelog, AI-disclosure and AI-in-changelog rules | CI |
| special changes | if `test/tolerances.toml` changes, the added CHANGELOG lines must contain "tolerance"; if `test/fixtures/fortran/` changes, "fixture"; if `legacy/` changes, "legacy/" | hook + CI |
| AI trailers | every AI tool named in a commit's `Co-Authored-By` trailer must appear in the *Tools* table of `AI_USAGE.md` | hook + CI |
| AI disclosure | exactly one of the two AI boxes in the PR template is ticked; if any commit has an AI trailer, "AI tools were used" must be ticked | CI |
| AI in the changelog | if AI tools were used, the added CHANGELOG lines mention "AI" | hook + CI |
| AI summary in step | if the *Summary* section of `AI_USAGE.md` changes, `paper/paper.md` must change too | hook + CI |
| model docs | if `src/model/` changes but neither `docs/src/model.md` nor `docs/src/porting_notes.md` does: warning only | hook + CI |
| API docs | undocumented exports, broken references and failing doctests fail the docs build | `Docs.yml`, `docs-build` hook |
| release placeholders | TODO placeholders in `AI_USAGE.md` and `paper/paper.md` warn on every push and PR; a tag is refused while any remain | `Metadata.yml` (warning), `Release.yml` (refusal), unchanged |

`Changes.yml` runs on `pull_request` (`opened`, `edited`, `synchronize`, `reopened`),
so editing the PR body re-runs it. It has no path filter, because a required check
that is skipped blocks merging.

The PR template keeps its two AI boxes. The CHANGELOG checkbox is replaced by a note
that `Changes.yml` checks the entry. `CONTRIBUTING.md` is updated to describe the
hooks and the rules above.

## What you need to do

### Before the first push
- [ ] **Commit what is staged now.** The staged tree mixes the CI/JOSS work with the
      JuliaFormatter 1.x reformat. Either split it into two commits (reformat first)
      or commit it as one, then put the reformat's SHA in `.git-blame-ignore-revs`.
- [ ] **Fill in placeholders.** `Release.yml` refuses to tag a release while any remain.
  - `PORT_AUTHOR_NAME` / `PORT_AUTHOR_EMAIL` in `Project.toml` and `CODE_OF_CONDUCT.md`.
  - The author TODOs in `CITATION.cff` (name, ORCID, affiliation).
  - `OWNER` in `README.md`, `CITATION.cff` and `.github/ISSUE_TEMPLATE/config.yml`.
- [ ] **Complete `AI_USAGE.md`.** List the tools and versions used for the original
      port, the AI involvement in each area, and your review process.
- [ ] **Review the new, unstaged changes** (`git diff`), then commit in this order:
  1. the staged work as it is (or split: the 1.x reformat first, then the CI/JOSS
     work);
  2. the hooks and checks from 12 November (everything unstaged), with a
     `Co-Authored-By` trailer for the AI assistant;
  3. the JuliaFormatter 2.x reformat on its own (next item).
  Add the SHA of each reformat commit to `.git-blame-ignore-revs`.
- [ ] **On your machine** (Windows, Julia ≥ 1.10, R):
  1. `julia --project=tools/format -e "using Pkg; Pkg.instantiate()"` and commit
     `tools/format/Manifest.toml`.
  2. Install prek 0.5.10 (`uv tool install prek==0.5.10`), then `prek install`.
  3. `prek run juliaformatter --all-files`: the 2.x reformat. Check that
     `git diff --stat -- legacy/ data/ test/fixtures/fortran/` is empty.
  4. `julia --project=. -e "using Pkg; Pkg.test()"` and
     `julia --project=. test/legacy_comparison/run_comparison.jl --no-plots` on the
     reformatted tree: both must pass unchanged.
  5. `SKIP=legacy-untouched prek run --all-files` (fixes `LICENSE` line endings, for
     example), then commit the reformat.
  6. `julia --project=docs docs/make.jl`.

### Once the repository exists on GitHub
- [ ] Push to a branch (not `main`), open a PR, and fix whatever fails on the first
      real run: macOS and Windows runners, Linux gfortran rounding, the CRAN snapshot,
      the fixture check, the docs preview without persisted credentials.
- [ ] Add a `CODECOV_TOKEN` repository secret (from codecov.io).
- [ ] After the first successful Docs run on `main`, enable GitHub Pages from the
      `gh-pages` branch.
- [ ] Enable Issues and Discussions. The issue-template "Question" link points to
      Discussions.
- [ ] Repository settings:
  - Actions: default workflow permissions read-only; Actions may not create or approve
    pull requests; approval required for workflows from outside contributors.
  - Security: secret scanning with push protection, Dependabot alerts, private
    vulnerability reporting.
- [ ] Add a branch ruleset on `main`, once every check below has reported at least
      once (GitHub only offers checks it has seen):
  - pull requests required (0 approvals: you cannot approve your own PR);
  - branches must be up to date before merging, because the tolerance checks must
    pass on the merged code, not on an old base;
  - linear history; no force pushes or deletion; no bypass, or bypass for emergencies
    only;
  - required checks: **CI result**, **Legacy comparison**, **Documentation**,
    **Formatting**, **Metadata**, **Changelog and AI usage**, **Lint**.
- [ ] Add a tag ruleset so only you can create `v*` tags.
- [ ] Turn on the repository in Zenodo's GitHub integration
      (<https://zenodo.org/account/settings/github/>).
- [ ] Check that Dependabot accepts the `julia` ecosystem entry. If it doesn't, replace
      it with a CompatHelper workflow.
- [ ] Open a test PR and confirm every check is green, the docs preview link appears,
      the legacy report shows in the job summary, and a PR without a CHANGELOG entry
      fails **Changelog and AI usage**.

### Before submitting to JOSS
- [ ] Finish `paper/paper.md`:
  - the author block (ORCIDs, affiliations, date);
  - *State of the field*;
  - *Research impact statement*;
  - *AI usage disclosure*, consistent with `AI_USAGE.md`;
  - funding.
- [ ] Check the section list and word limits against the current JOSS author guidelines.
- [ ] Download the PDF from the Paper workflow and proofread it.
- [ ] Release:
  1. Mark the CHANGELOG `## 0.1.0` section as released.
  2. Make sure the versions in `Project.toml` and `CITATION.cff` agree.
  3. Tag `v0.1.0` and push the tag. Zenodo mints a DOI.
- [ ] Add the Zenodo DOI to `CITATION.cff` (`doi:`) and to the README badge.
- [ ] Submit at <https://joss.theoj.org>.

### After JOSS acceptance
- [ ] Make the JOSS article the `preferred-citation` in `CITATION.cff` and add the JOSS
      badge to the README.

### Later
- [ ] When validation against R/Fortran is no longer needed, retire the live comparison
      (see *Dropping the live comparison later* above).
- [ ] Move the R snapshot date and R version forward deliberately, after `Weekly.yml`
      shows the newer toolchain passes.

## Open questions and risks

1. **Very new tool versions.** JuliaFormatter 2.14.11 (10 November) is the latest of
   eleven 2.14.x releases in 13 days; prek 0.5.10 (4 November) and zizmor 1.32.0
   (3 November) are also under two weeks old. I have not read what changed in them.
   If the reformat looks wrong, pin an earlier 2.14.x in `tools/format` (its own
   commit) and reformat again.
2. **Not yet verified:** that the P3M snapshot URL serves `lhs`, `CholWishart` and
   `abind` for `noble`; that Julia on Linux matches the fresh Linux Fortran within
   `test/tolerances.toml` for the generated `ci` fixtures; that `.JuliaFormatter.toml`
   (`style = "blue"`, `margin = 120`) gives the intended layout under 2.x; that
   Documenter deploys without persisted credentials (it builds its push URL from
   `GITHUB_TOKEN`).
3. **The CHANGELOG rule applies to every PR**, including CI-only and typo fixes. Group
   such entries under a heading such as "Maintenance" in the unreleased section.
