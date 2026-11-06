# Test fixtures

`fortran/` holds golden-master outputs of the legacy Fortran model. Each fixture set
`<label>_*.csv` contains inputs *and* outputs, so `test/regression/test_fortran_golden.jl`
needs neither R, nor a Fortran compiler, nor random numbers.

## Format

| File | Contents |
|---|---|
| `<label>_inputs.csv` | one row per case: `case`, `iteration_threshold`, the 56 constants (canonical names, see `CONSTANT_PARAMETER_NAMES`), and the 12 forcings as `<forcing>_<k>` for steps `k = 1..58` (570 → 0 Ma) |
| `<label>_main_{co2,o2,temp15}.csv` | output of `run_geocarb.f90`; one row per case, columns `step_1..step_58` |
| `<label>_supp_<variant>_{co2,o2,temp15}.csv` | output of `run_geocarb_supp.f90` for the variants `control`, `gym`, `timing`, `gym_timing`, `dT2X`, `gym_timing_dT2X` (optional) |

Temperatures are stored as `temp + 15`, the quantity the R code exports. Failed steps
appear as `inf` (CO2, O2) exactly as the Fortran wrote them.

## The shipped `original` fixtures

The `original_*` files were produced by the **unmodified R/Fortran code** (the DLLs
compiled by R with its own gfortran, Rtools 4.5 / gfortran 14.3 on Windows): the first
100 prior samples of the legacy comparison (`test/legacy_comparison/run_legacy.R`,
seed 2026, `iteration_threshold = 10`) and the same 100 samples through the six
supplemental variants. They were converted from the R exports in
`test/legacy_comparison/output/` to the format above. The values are full-precision
decimal representations of the Fortran's doubles.

## Regenerating, or adding another build

`generate_fortran_fixtures.jl` calls compiled Fortran libraries directly with `ccall`
and writes a new fixture set (300 prior draws plus edge cases):

```text
# in legacy/fortran: the original build, and a build with double-precision literals
gfortran -shared -fPIC -fno-range-check -o original/run_geocarb.so src/run_geocarb.f90
gfortran -shared -fPIC -fno-range-check -o original/run_geocarb_supp.so src/run_geocarb_supp.f90
gfortran -shared -fPIC -fno-range-check -fdefault-real-8 -o real8/run_geocarb.so src/run_geocarb.f90
gfortran -shared -fPIC -fno-range-check -fdefault-real-8 -o real8/run_geocarb_supp.so src/run_geocarb_supp.f90

julia --project=. test/fixtures/generate_fortran_fixtures.jl legacy/fortran/original original
julia --project=. test/fixtures/generate_fortran_fixtures.jl legacy/fortran/real8 real8
```

On Windows use `.dll` instead of `.so`. Running the generator with label `original`
overwrites the shipped files.

## How the golden test judges a fixture

The test runs Julia with `fortran_single_literals = true` (the v1 default) for every
label except `real8`, which uses `false`. For each quantity it requires

* the positions of `inf`/`NaN` to be identical (same steps fail);
* values **before** a run's first failed step to agree within `rtol = 1e-8`;
* values **at or after** the first failed step to agree within `rtol = 1e-4`.

The split exists because Julia's `exp`/`log`/`^` and the C runtime used by gfortran
round differently in the last bit now and then. In a healthy run that stays below
about 4e-9 relative. After a failed step the legacy model keeps integrating from an
invalid state, which amplifies those last-bit differences up to about 1e-6. See
`docs/src/testing.md` for details.
