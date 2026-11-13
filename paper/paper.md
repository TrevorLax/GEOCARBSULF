---
title: 'GeocarbPrecalibration.jl: a tested, reproducible Julia implementation of the GEOCARBSULFvolc carbon-cycle model and its precalibration'
tags:
  - Julia
  - carbon cycle
  - paleoclimate
  - GEOCARB
  - climate sensitivity
  - uncertainty quantification
authors:
  - name: TODO Port Author
    orcid: 0000-0000-0000-0000 # TODO
    corresponding: true
    affiliation: 1
  - name: Tony E. Wong
    orcid: 0000-0000-0000-0000 # TODO
    affiliation: 2 # TODO
affiliations:
  - name: TODO, Country
    index: 1
  - name: TODO, Country
    index: 2
date: TODO 2026
bibliography: paper.bib
---

<!--
JOSS draft. Before submitting, check the section list and word limits against the
current author guidelines (https://joss.readthedocs.io), resolve every TODO
(Release.yml refuses to tag a release with TODOs left), and keep the
"AI usage disclosure" section consistent with AI_USAGE.md.
-->

# Summary

Long-term carbon-cycle models reconstruct atmospheric CO2, O2 and surface
temperature over the Phanerozoic (the last 570 million years) from the balance of
carbon and sulfur fluxes between rocks, oceans and the atmosphere. Comparing these
reconstructions with proxy records constrains Earth-system sensitivity, which is the
long-term warming caused by a doubling of CO2 [@Park2011; @Royer2014].
GeocarbPrecalibration.jl is a Julia [@Bezanson2017] implementation of the
GEOCARBSULFvolc model [@Berner2004; @Berner2006a; @Berner2006b; @Berner2008] together with
the Latin-hypercube *precalibration* workflow of @Wong2021. That workflow samples 56
uncertain constant parameters and 12 uncertain time series. It runs the model for each
sample and keeps the samples whose CO2 and temperature trajectories agree with proxy
windows [@Foster2017; @Mills2019].

# Statement of need

The precalibration of @Wong2021 was published as R driver scripts calling a compiled
Fortran model, with experiments configured by editing the scripts. That code
reproduces the paper, but it is hard to extend, test, parallelise or reuse:

- model variants are separate copies of the Fortran;
- results depend on the execution path;
- there are no automated tests.

GeocarbPrecalibration.jl gives the same model and workflow as one documented Julia
package for researchers in paleoclimate and Earth-system science:

- experiments are declared in TOML files;
- model variants are options;
- ensembles run in deterministic, threaded, checkpointable chunks, with results that
  do not depend on the number of threads;
- numerical failures are reported per time step and never stop an ensemble;
- analysis and plotting functions reproduce the published figures and numbers.

The package lets users repeat, vary and extend the analysis of @Wong2021, for example
with new proxy data, priors or acceptance rules, without touching the model source.

# State of the field

<!-- TODO (authors): extend with the implementations you know of and how this package differs. -->
GEOCARB-family models [@Berner2001; @Berner2004; @Berner2006a] have been distributed
mainly as Fortran and spreadsheet implementations, such as the GEOCARBSULF code used in
@Park2011 and @Royer2014, and as the R/Fortran precalibration code of @Wong2021.
Process-based alternatives such as COPSE [@Lenton2018] and the temperature
reconstruction of @Mills2019 address related questions with different model
structures. To our knowledge, no other open, tested implementation of GEOCARBSULFvolc
and its precalibration exists that is checked continuously against the original code.

# Software design

The model is a line-by-line port of the Fortran, split into small documented
functions (climate, vegetation, fluxes, the CO2 Newton solver, strontium). Parameters
are addressed by name and never by position. The supplemental experiments of the
original code are `ModelOptions` fields whose defaults reproduce the legacy model.

Faithfulness to the original is treated as a testable property:

- The unmodified R/Fortran code is kept in the repository.
- Continuous integration runs it on every change. It checks that Julia reproduces CO2,
  O2 and temperature for 1000 prior samples and six supplemental variants, within a
  relative tolerance of $10^{-8}$ (or $10^{-4}$ after a run's first failed step), with
  identical failure positions and acceptance statistics.
- Golden-master fixtures from the compiled Fortran pin the results on Linux, macOS and
  Windows without needing R.

During the port, a review of the original code found discrepancies in it. For
example, gfortran stores decimal literals in single precision. These findings are
documented, reproduced by default, and can be corrected through opt-in options. The
test suite also covers:

- statistical properties of the samplers;
- determinism across thread counts;
- checkpoint and resume;
- zero-allocation model runs;
- doctests of every documented example.

# Research impact statement

<!-- TODO (authors): describe current and expected use: projects, students, follow-up studies, planned extensions (e.g. new proxy compilations or calibration methods). -->
The package reproduces all experiments of @Wong2021 (main, supplemental and
Cretaceous) from configuration files, and supports new precalibration studies of
Earth-system sensitivity. TODO.

# AI usage disclosure

<!-- Keep consistent with AI_USAGE.md (the full report, also published in the documentation). -->
TODO (authors): one-paragraph summary of `AI_USAGE.md`. Name the generative-AI tools
and versions used and the parts of the software, documentation and paper they
assisted with. Explain how their output was reviewed and verified (the continuous
comparison against the original R/Fortran code, golden-master fixtures, tests and
doctests). State that the authors take full responsibility for all content. The full
report is in `AI_USAGE.md` and on the "AI usage" page of the documentation.

# Acknowledgements

We thank Ying Cui, co-author of the original R/Fortran code, and Dana L. Royer and
Klaus Keller, co-authors of @Wong2021. TODO (authors): funding.

# References
