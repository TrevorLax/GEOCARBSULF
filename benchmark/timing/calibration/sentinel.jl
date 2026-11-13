# sentinel.jl: fixed calibration kernel (plan §6.4). Run at the start, middle and end of a
# session; a change of more than 5 % between runs flags the session in the report.
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
using LinearAlgebra: BLAS
job = read_job(ARGS[1])
w = RawWriter(job)
BLAS.set_num_threads(1)
function scalar_kernel(n)
    s = 0.0
    for i in 1:n
        s += log(1.0 + exp(-i * 1e-7))
    end
    return s
end
A = [sin(i + j) for i in 1:200, j in 1:200];
B = copy(A);
scalar_kernel(10);
A * B;
for (name, f) in (("exp/log loop (10^7)", () -> scalar_kernel(10_000_000)), ("200x200 matmul x50", () -> (
    for _ in 1:50
        A * B
    end
)))
    t = minimum(per_call(f, 1) for _ in 1:5)
    record!(
        w;
        variant="J",
        component="SENT",
        subcomponent=name,
        workload=jstr(job, "position"),
        wall_s=t,
        threads=1,
        notes="minimum of 5",
    )
end
