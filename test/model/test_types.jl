@testset "ConstantParams" begin
    p = mean_constants(PRIOR_TABLE)
    @test p isa ConstantParams{Float64}
    @test p.deltaT2X == 3.0
    @test p[:GLAC] == 2.0
    v = parameter_vector(p)
    @test length(v) == 56
    names = collect(CONSTANT_PARAMETER_NAMES)
    @test ConstantParams(names, v) == p
    perm = reverse(1:56)
    @test ConstantParams(names[perm], v[perm]) == p           # order does not matter
    @test ConstantParams(String.(names), v) == p              # strings are fine
    d = Dict{Symbol,Float64}(n => getfield(p, n) for n in CONSTANT_PARAMETER_NAMES)
    delete!(d, :ACT)
    @test_throws ArgumentError ConstantParams(d)               # missing name
    d[:ACT] = 0.09
    d[:bogus] = 1.0
    @test_throws ArgumentError ConstantParams(d)               # unknown name
    @test_throws ArgumentError ConstantParams(names, v[1:10])  # length mismatch
    q = update(p; deltaT2X=4.0)
    @test q.deltaT2X == 4.0 && q.GLAC == p.GLAC
    @test_throws ArgumentError update(p; nope=1.0)
    @test G._constants_from_vector(Float64, v) == p
    @test parameter_units(:deltaT2X) == "°C"
    @test !isempty(parameter_description(:Fwsi_0))
    @test !isempty(parameter_description(:GEOG))
    @test_throws ArgumentError parameter_description(:nope)
    @test all(n -> haskey(G.PARAMETER_INFO, n), CONSTANT_PARAMETER_NAMES)
    @test all(n -> haskey(G.PARAMETER_INFO, n), TIME_FORCING_NAMES)
end

@testset "TimeForcings" begin
    f = TIME_PRIOR.center
    @test length(f) == 58
    @test f.age[1] == 570 && f.age[end] == 0
    @test f[:Sr] === f.Sr
    d = Dict{Symbol,Vector{Float64}}(n => copy(getfield(f, n)) for n in TIME_FORCING_NAMES)
    @test TimeForcings(f.age, d) == f
    @test_throws ArgumentError TimeForcings(reverse(f.age), d)       # ages must decrease
    @test_throws ArgumentError TimeForcings(f.age .+ 10, d)          # 580 Ma is outside the model
    d2 = copy(d)
    d2[:Sr] = d[:Sr][1:10]
    @test_throws ArgumentError TimeForcings(f.age, d2)               # length mismatch
    d3 = copy(d)
    d3[:Sr] = copy(d[:Sr])
    d3[:Sr][3] = NaN
    @test_throws ArgumentError TimeForcings(f.age, d3)               # non-finite value
    @test TimeForcings(f.age, d3; check_finite=false) isa TimeForcings
    d4 = copy(d)
    delete!(d4, :fC)
    @test_throws ArgumentError TimeForcings(f.age, d4)               # missing forcing
    m = G.forcing_matrix(f)
    @test size(m) == (58, 12)
    @test m[:, 7] == f.fAw_fA && m[:, 9] == f.GEOG                   # Fortran Matrix_12 order
    g = copy(f)
    g.Sr[1] = -1.0
    @test f.Sr[1] != -1.0                                            # copy is deep
end

@testset "ModelOptions" begin
    o = ModelOptions()
    @test o == G.DEFAULT_MODEL_OPTIONS
    @test o.glacial_intervals == [(260.0, 330.0), (-Inf, 40.0)]
    @test o.gym_angio_transition == (130.0, 80.0) && o.gym_factor == 1.0 && !o.dT2X_ramp
    @test_throws ArgumentError ModelOptions(dt=-1)
    @test_throws ArgumentError ModelOptions(gym_angio_transition=(60, 110))
    @test_throws ArgumentError ModelOptions(iteration_threshold=0)
    @test_throws ArgumentError ModelOptions(gym_factor=-1)
    @test_throws ArgumentError ModelOptions(rco2_bounds=(2.0, 1.0))
    o2 = G.model_options_from_dict(Dict("gym_angio_transition" => [110, 60], "gym_factor" => 0.25, "dT2X_ramp" => true))
    @test o2.gym_angio_transition == (110.0, 60.0) && o2.gym_factor == 0.25 && o2.dT2X_ramp
    @test_throws ArgumentError G.model_options_from_dict(Dict("bogus" => 1))
    @test G.model_options_from_dict(G.options_dict(o2)) == o2
    k1 = G.resolve_constants(ModelOptions(; fortran_single_literals=true))
    @test k1.ln2 == Float64(Float32(log(2.0)))
    @test k1.tol == Float64(0.01f0) && k1.sr_offset == Float64(0.7f0) && k1.damping == Float64(0.9f0)
    @test o.fortran_single_literals                       # v1 default: the compiled Fortran's literals
    @test G.resolve_constants(o) == k1
    k0 = G.resolve_constants(ModelOptions(; fortran_single_literals=false))
    @test k0.tol == 0.01 && k0.sr_offset == 0.7 && k0.ln2 == log(2.0)
    @test k0.ln2 != k1.ln2 && k0.tol != k1.tol
end
