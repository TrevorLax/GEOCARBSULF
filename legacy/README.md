# Legacy R/Fortran code (unmodified)

This folder is an exact copy of the original `GEOCARB-precalibration` code: `R/`,
`fortran/` and `input_data/`, the original README (`README_original.md`) and licence.
It is kept only as the **test oracle** for the Julia port. Nothing in it is used by
the Julia package except `test/legacy_comparison/`, which runs it to check that the
Julia code reproduces it.

Do not edit these files. Once the scientific owners have signed off on parity
(plan phase 8), this folder can be removed and the reference preserved with a git tag.

`fortran/run_geocarb.dll` is the Windows build that was in the original folder. The
comparison test compiles `run_geocarb_supp` (and, on Linux/macOS, both libraries) with
`R CMD SHLIB` when they are missing.
