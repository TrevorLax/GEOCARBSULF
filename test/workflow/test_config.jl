@testset "experiment configuration" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    main = load_experiments(joinpath(root, "experiments", "main", "grid.toml"))
    @test length(main) == 15
    @test [c.constraint for c in main[1:5]] == fill(:co2, 5)
    @test [c.threshold for c in main[1:5]] == [0.30, 0.35, 0.40, 0.45, 0.50]
    c11 = main[11]                                      # lhs_driver.R: idx_experiment 11
    @test c11.constraint == :both && c11.threshold == 0.30 && c11.seed == 13574 && c11.tag == "ct_out30"
    @test main[6].tag == "t_out30" && main[5].tag == "c_out50"
    @test all(isfile(c.prior_file) && isfile(c.time_array_file) for c in main)
    @test main[1].model == ModelOptions()

    extra = load_experiments(joinpath(root, "experiments", "main", "ct_out30_extra_seeds.toml"))
    @test [c.seed for c in extra] == [11, 2020]
    @test [c.tag for c in extra] == ["ct_out30_seed11", "ct_out30_seed2020"]

    # every shipped configuration loads and validates
    for (dir, _, files) in walkdir(joinpath(root, "experiments")), f in files
        endswith(f, ".toml") || continue
        for c in load_experiments(joinpath(dir, f))
            @test validate(c) === c
        end
    end
    sup = only(load_experiments(joinpath(root, "experiments", "supplemental", "gym_timing_dT2X.toml")))
    @test sup.model.gym_angio_transition == (110.0, 60.0) && sup.model.gym_factor == 0.25 && sup.model.dT2X_ramp
    @test sup.tag == "ct_out50_gym+timing+dT2X"
    cret = only(load_experiments(joinpath(root, "experiments", "cretaceous", "stage1.toml")))
    @test cret.cretaceous_age == 90.0 && cret.run_on_time_centers
    @test build_rule(cret) isa AllOf && length(build_rule(cret).rules) == 3

    # errors
    @test_throws ArgumentError load_experiments(tmpfile("nmae = \"typo\"\n"; ext=".toml"))
    @test_throws ArgumentError load_experiments(tmpfile("[grid]\nthreshhold = [0.3]\n"; ext=".toml"))
    @test_throws ArgumentError load_experiments(tmpfile("[model]\ngym_fac = 0.5\n"; ext=".toml"))
    @test_throws ArgumentError load_experiments(tmpfile("data_choice = \"PR2011\"\n"; ext=".toml"))
    @test_throws ArgumentError validate(small_config(; threshold=0.0))
    @test_throws ArgumentError validate(small_config(; constraint=:o2))
    @test_throws ArgumentError validate(small_config(; prior_file="nope.csv"))
    @test_throws ArgumentError validate(with_overrides(small_config(); seed=-1))
    @test default_tag(:temp, 0.35) == "t_out35"
end
