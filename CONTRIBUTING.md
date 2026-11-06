# Contributing

- **Style**: [BlueStyle](https://github.com/JuliaDiff/BlueStyle) (`.JuliaFormatter.toml`).
  Keep the physics variable names of Berner / the Fortran (`Fwsi_0`, `dlsy`, …) so the
  code can be traced to the literature, and document each one.
- **Tests**: every change needs a test. Run `julia --project=. -e "using Pkg; Pkg.test()"`.
  If you touch `src/model/`, also run `test/legacy_comparison/run_comparison.jl`.
- **Do not "simplify" the model expressions** in `src/model/co2_solver.jl` and
  friends. They follow the Fortran's order of operations so that results agree to
  rounding error.

## Adding a constant parameter or forcing

1. add the name to `CONSTANT_PARAMETER_NAMES` (or `TIME_FORCING_NAMES`) and its
   description and units to `PARAMETER_INFO` in `src/parameters/names.jl`;
2. add the field to `ConstantParams` (or `TimeForcings`);
3. add the row (or columns) to the input CSV in `data/`;
4. use it in `src/model/`, and add a unit test and a note in `docs/src/porting_notes.md`.

## Adding a model variant

Add a `ModelOptions` field whose default keeps today's behaviour, implement it,
validate it in `validate(::ModelOptions)`, and test both the default (the legacy
comparison must still pass) and the new behaviour.

## Regenerating fixtures

See `test/fixtures/README.md` and `test/legacy_comparison/README.md`.
