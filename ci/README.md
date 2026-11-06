# Continuous integration

GitHub Actions workflows for this repository. Move them into place to enable them:

```text
mkdir .github\workflows
move ci\github-workflows\*.yml .github\workflows\
```

- `CI.yml`: test matrix (Linux, macOS, Windows × Julia 1.10 LTS and latest, plus a
  4-thread job), coverage, and the comparison with the original R/Fortran code (R and
  gfortran on Ubuntu).
- `Docs.yml`: builds the Documenter site and deploys it on pushes to `main`. Set
  `DOCS_REPO` in `docs/make.jl` (or the environment) to the repository URL.
- `Format.yml`: checks BlueStyle formatting with JuliaFormatter (advisory).
