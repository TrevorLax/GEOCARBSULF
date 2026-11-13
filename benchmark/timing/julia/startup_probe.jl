# startup_probe.jl: in-process part of the cold-start measurements (plan §3.1). Run in a
# fresh process by run_timing.jl, which also times the whole process from outside.
#   S1  `using GeocarbPrecalibration` (in process)
#   S2  input set-up: first call and warm
#   S3  first model call (includes compilation) and a warm call
t_using = @elapsed using GeocarbPrecalibration
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
job = read_job(ARGS[1])
w = RawWriter(job)
record!(
    w; variant="J", component="S1", subcomponent="using GeocarbPrecalibration (in process)", mode="cold", wall_s=t_using
)
function setup_inputs()
    table = read_prior_table(datapath("GEOCARB_input_summaries_calib_all.csv"))
    priors = build_priors(table)
    tp = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
    proxy = read_proxy_data(datapath("CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv"))
    tw = temperature_windows(read_temperature_data(datapath("Mills_GR_2019_temp_co2.csv")), tp.center.age)
    cw = co2_windows(proxy, tp.center.age)
    dof = inverse_wishart_dof(tp.sigma, read_variance_reduction())
    return (table=table, priors=priors, tp=tp, cw=cw, tw=tw, dof=dof)
end
m = measure(setup_inputs)
record!(w, m; variant="J", component="S2", subcomponent="input set-up", mode="first_call")
m2 = measure(setup_inputs)
record!(w, m2; variant="J", component="S2", subcomponent="input set-up", mode="warm")
s = m.value
p = mean_constants(s.table)
m = measure(() -> run_geocarb(p, s.tp.center))
check(succeeded(m.value), "prior-mean run failed")
record!(w, m; variant="J", component="S3", subcomponent="first run_geocarb", mode="first_call")
m = measure(() -> run_geocarb(p, s.tp.center))
record!(w, m; variant="J", component="S3", subcomponent="run_geocarb", mode="warm")
