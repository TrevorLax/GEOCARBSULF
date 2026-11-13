# bench_constraints.jl: Julia side of the constraint components (plan §3.4)
#   C1  legacy_percent_outbound on the 1000 exported CO2 and temperature series
#   C2  acceptance-rule evaluation (AllOf(OutboundRule(:co2), OutboundRule(:temp))) per sample

include(joinpath(@__DIR__, "..", "lib", "common.jl"))
job = read_job(ARGS[1])
w = RawWriter(job)
using GeocarbPrecalibration
const GP = GeocarbPrecalibration
include_legacy_helpers()

exports = jstr(job, "exports_dir")
tp = read_time_arrays(datapath("GEOCARB_input_arrays_NewDegassing.csv"))
const age = tp.center.age
proxy = read_proxy_data(datapath("CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv"))
const cw = co2_windows(proxy, age)
const tw = temperature_windows(read_temperature_data(datapath("Mills_GR_2019_temp_co2.csv")), age)
_, co2m = read_matrix(joinpath(exports, "legacy_co2.csv"))
_, tempm = read_matrix(joinpath(exports, "legacy_temp_plus15.csv"))
_, ref = read_matrix(joinpath(exports, "legacy_prcout.csv"))
const co2 = [co2m[i, :] for i in axes(co2m, 1)]
const temp = [tempm[i, :] for i in axes(tempm, 1)]
const n = length(co2)

function all_prcout!(pc, pt)
    @inbounds for i in 1:n
        pc[i] = legacy_percent_outbound(co2[i], cw)
        pt[i] = legacy_percent_outbound(temp[i], tw)
    end
end

component!(w, "J", "C1"; workload="legacy_$n") do
    pc = zeros(n)
    pt = zeros(n)
    all_prcout!(pc, pt)
    check(
        isequal(pc, ref[:, 1]) && isequal(pt, ref[:, 2]), "legacy_percent_outbound does not reproduce legacy_prcout.csv"
    )
    k = calls_for(() -> all_prcout!(pc, pt))
    t = per_call(() -> all_prcout!(pc, pt), k)
    return record!(
        w;
        variant="J",
        component="C1",
        subcomponent="legacy_percent_outbound",
        workload="legacy_$n",
        n=2n * k,
        wall_s=t / 2n,
        notes="seconds per series",
    )
end

# Model results rebuilt from the exports (temp without the +15 the R code added).
function result_of(i)
    r = GeocarbResult{Float64}(age)
    r.co2 .= co2[i]
    r.temp .= temp[i] .- 15.0
    r.o2 .= 0.0
    r.status .= [isinf(x) ? NotConverged : Converged for x in co2[i]]
    return r
end
const results = [result_of(i) for i in 1:n]
const ctx = EvaluationContext(cw, tw; T0=15.0)
const rule = AllOf(OutboundRule(:co2, 0.5), OutboundRule(:temp, 0.5))
count_accepted() = count(r -> accepts(rule, r, ctx), results)

component!(w, "J", "C2"; workload="legacy_$n") do
    na = count_accepted()
    check(na == count(i -> ref[i, 1] <= 0.5 && ref[i, 2] <= 0.5, 1:n), "acceptance count differs from R")
    k = calls_for(count_accepted)
    t = per_call(count_accepted, k)
    return record!(
        w;
        variant="J",
        component="C2",
        subcomponent="accepts(AllOf(OutboundRule...))",
        workload="legacy_$n",
        n=n * k,
        wall_s=t / n,
        notes="seconds per sample (computes both % outbound)",
    )
end
