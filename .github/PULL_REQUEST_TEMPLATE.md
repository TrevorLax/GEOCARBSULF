## What and why

<!-- What does this change, and why? Link related issues (Fixes #123). -->

## Checklist

- [ ] Tests added or updated; `julia --project=. -e "using Pkg; Pkg.test()"` passes
- [ ] The legacy comparison passes (the prek pre-push hook runs it; CI runs it as
      "Legacy comparison")
- [ ] Documentation and doctests updated (`julia --project=docs docs/make.jl`)
- [ ] Formatted (the prek hook, or `prek run juliaformatter --all-files`)
- [ ] `CHANGELOG.md` entry added under the unreleased section (required; checked by
      "Changelog and AI usage"). Name any change to tolerances, fixtures or `legacy/`.

## AI usage

<!-- Tick exactly one box (checked by "Changelog and AI usage"). If AI tools were
     used, mention AI in the CHANGELOG entry and list the tool in AI_USAGE.md. -->

- [ ] No generative-AI tools were used for this change, **or**
- [ ] AI tools were used. Tool(s) and what for: <!-- e.g. "Claude, drafting tests" -->
      I have reviewed, understood and tested all AI-assisted changes.
