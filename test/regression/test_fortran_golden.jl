# Golden master: Julia vs stored outputs of the compiled legacy Fortran.
#
# Fixtures (test/fixtures/fortran/<label>_*.csv) hold inputs and outputs, so this test
# needs neither R nor a Fortran compiler. Judged like the legacy comparison:
#   * pass/fail (Inf/NaN) positions identical;
#   * values before a run's first failed step within rtol_clean (1e-8);
#   * values at/after a failed step within rtol_post (1e-4; rounding differences between
#     maths libraries are amplified there; see docs/src/testing.md).
# The tolerances are read from test/tolerances.toml, shared with the legacy comparison.
# Temperatures are stored and compared as temp + 15, the quantity R exports.

@testset "golden master vs compiled Fortran" begin
    dir = joinpath(@__DIR__, "..", "fixtures", "fortran")
    labels =
        isdir(dir) ? [replace(f, "_inputs.csv" => "") for f in readdir(dir) if endswith(f, "_inputs.csv")] : String[]
    if isempty(labels)
        @info "no Fortran fixtures in test/fixtures/fortran; see test/fixtures/README.md (golden test skipped)"
        @test_skip "golden-master fixtures not generated"
    end
    tol = G.TOML.parsefile(joinpath(@__DIR__, "..", "tolerances.toml"))
    rtol_clean, rtol_post, atol = Float64(tol["rtol_clean"]), Float64(tol["rtol_post"]), Float64(tol["atol"])
    age = collect(570.0:-10.0:0.0)
    nt = length(age)
    steps = ["step_$k" for k in 1:nt]
    for label in labels
        t = read_csv_table(joinpath(dir, "$(label)_inputs.csv"))
        single = label != "real8"           # real8 fixtures: Fortran built with -fdefault-real-8
        cases = Tuple{ConstantParams{Float64},TimeForcings{Float64},Int}[]
        for row in t.rows
            num(name) = G.parse_number(row[findfirst(==(name), t.header)])
            p = ConstantParams(collect(CONSTANT_PARAMETER_NAMES), [num(String(n)) for n in CONSTANT_PARAMETER_NAMES])
            d = Dict{Symbol,Vector{Float64}}(n => [num("$(n)_$k") for k in 1:nt] for n in TIME_FORCING_NAMES)
            push!(cases, (p, TimeForcings(age, d; check_finite=false), Int(num("iteration_threshold"))))
        end
        variants = Tuple{String,Any}[("main", (; kw...) -> ModelOptions(; kw...))]
        for (nm, b, e, g, dd) in [
            ("control", 130, 80, 1, -1),
            ("gym", 130, 80, 0.25, -1),
            ("timing", 110, 60, 1, -1),
            ("gym_timing", 110, 60, 0.25, -1),
            ("dT2X", 130, 80, 1, 1),
            ("gym_timing_dT2X", 110, 60, 0.25, 1),
        ]
            isfile(joinpath(dir, "$(label)_supp_$(nm)_co2.csv")) || continue
            push!(
                variants,
                (
                    "supp_$nm",
                    (; kw...) -> ModelOptions(; gym_angio_transition=(b, e), gym_factor=g, dT2X_ramp=dd >= 0, kw...),
                ),
            )
        end
        for (name, mk) in variants
            ref = Dict{String,Matrix{Float64}}()
            for q in ("co2", "o2", "temp15")
                tq = read_csv_table(joinpath(dir, "$(label)_$(name)_$(q).csv"))
                ref[q] = reduce(hcat, [G.numeric_column(tq, s; allow_missing=true) for s in steps])   # cases × steps
            end
            n = size(ref["co2"], 1)
            n <= length(cases) || error("$label $name: more output rows than input cases")
            jl = Dict(q => Matrix{Float64}(undef, n, nt) for q in ("co2", "o2", "temp15"))
            for i in 1:n
                p, f, thr = cases[i]
                r = run_geocarb(p, f; options=mk(; fortran_single_literals=single, iteration_threshold=thr))
                jl["co2"][i, :] .= r.co2
                jl["o2"][i, :] .= r.o2
                jl["temp15"][i, :] .= r.temp .+ 15
            end
            post = cumsum(isinf.(ref["co2"]); dims=2) .> 0
            same(x, y) = (isnan(x) == isnan(y)) && (isinf(x) == isinf(y)) && (!isinf(x) || x == y)
            within(x, y, rtol) = !(isfinite(x) && isfinite(y)) || abs(x - y) <= atol + rtol * max(abs(x), abs(y))
            for q in ("co2", "o2", "temp15")
                J, R = jl[q], ref[q]
                @test all(same(J[I], R[I]) for I in CartesianIndices(J))
                @test all(within(J[I], R[I], post[I] ? rtol_post : rtol_clean) for I in CartesianIndices(J))
            end
        end
    end
end
