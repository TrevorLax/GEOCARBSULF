# Pinned environment for the published results

Published numbers should be traceable to exact dependency versions. StableRNGs fixes
the random stream, but Distributions.jl or StatsBase can change results between
versions. The repository's top-level `Manifest.toml` is git-ignored, so this directory
holds the environment the paper's experiments were run with.

**The `Manifest.toml` is not committed yet.** It has to be created on the machine,
and with the Julia version, that run the paper's experiments:

```sh
julia --project=reproduce -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=reproduce -t auto scripts/run_experiment.jl experiments/main/grid.toml
git add reproduce/Manifest.toml
```

Run the experiments with `--project=reproduce` from then on. Every result also records
the active project, the SHA-256 of its manifest and the versions of the package's direct
dependencies in its provenance (`environment_provenance()`), so a result can be checked
against this manifest:

```julia
using GeocarbPrecalibration, SHA
res = load_result("results/main/ct_out30/result.jld2")
res.provenance["manifest_sha256"] == bytes2hex(open(sha256, "reproduce/Manifest.toml"))
```
