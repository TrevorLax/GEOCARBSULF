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
    q = update_params(p; deltaT2X=4.0)
    @test q.deltaT2X == 4.0 && q.GLAC == p.GLAC
    @test_throws ArgumentError update_params(p; nope=1.0)
    # generic names are no longer exported; the old names still work qualified (J-32)
    exported = Base.names(GeocarbPrecalibration)
    @test !any(in(exported), (:update, :temperature, :validate))
    @test (@test_deprecated G.update(p; deltaT2X=4.0)) == update_params(p; deltaT2X=4.0)
    @test (@test_deprecated G.validate(ModelOptions())) == ModelOptions()
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
    # options are immutable: the shared default cannot be changed in place (J-19)
    @test_throws Exception G.DEFAULT_MODEL_OPTIONS.glacial_intervals[1] = (0.0, 1.0)
    @test_throws Exception push!(G.DEFAULT_MODEL_OPTIONS.glacial_intervals, (0.0, 1.0))
    @test G.DEFAULT_MODEL_OPTIONS == ModelOptions()
    src = [(260.0, 330.0), (-Inf, 40.0)]
    oc = ModelOptions(; glacial_intervals=src)
    src[1] = (0.0, 1.0)                                  # the caller's vector is copied
    @test oc.glacial_intervals[1] == (260.0, 330.0)
    # isequal is consistent with hash (Dict/Set contract)
    oz = ModelOptions(; dT2X_ramp_interval=(130.0, 0.0))
    ozm = ModelOptions(; dT2X_ramp_interval=(130.0, -0.0))
    @test oz == ozm && !isequal(oz, ozm) && hash(oz) != hash(ozm)
    @test isequal(ModelOptions(), ModelOptions()) && hash(ModelOptions()) == hash(ModelOptions())
    @test length(Set([ModelOptions(), ModelOptions()])) == 1
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
    # only the Fortran default literals are rounded; values set by the user are not (J-07)
    ku = G.resolve_constants(ModelOptions(; convergence_tol=1e-6, newton_damping=0.85, rco2_bounds=(0.5, 300.0)))
    @test ku.tol == 1e-6 && ku.damping == 0.85 && ku.rco2_min == 0.5 && ku.rco2_max == 300.0
    @test ku.shrink == Float64(0.2f0) && ku.pd_rco2_min == Float64(0.8f0)       # still at their defaults
    @test_throws ArgumentError ModelOptions(iteration_threshold=1)              # J-26: could never converge
    @test ModelOptions(; iteration_threshold=2).iteration_threshold == 2
end
