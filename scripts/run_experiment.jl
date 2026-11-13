#!/usr/bin/env julia
#
# Run the precalibration experiments described in an experiment TOML file.
#
#   julia --project=. -t auto scripts/run_experiment.jl CONFIG.toml [options]
#
# Options:
#   --only KEY=VALUE   run only the experiments whose tag, constraint, threshold or seed
#                      equals VALUE (repeatable; all filters must match), e.g.
#                      --only tag=ct_out30   or   --only constraint=both --only threshold=0.3
#   --dry-run          validate the configuration, read all inputs and run one small chunk
#   --checkpoint       write finished chunks to <output_dir>/<tag>/checkpoints and reuse them
#   --quiet            no progress messages
#
# Results go to <output_dir>/<tag>/: result.jld2, constants.csv, prcout.csv and
# provenance.toml. Replaces lhs_driver.R, lhs_driver_supp.R, lhs_driver_cret.R and
# run_experiment.R.

using GeocarbPrecalibration

function main(args)
    isempty(args) && (
        println(stderr, "usage: run_experiment.jl CONFIG.toml [--only KEY=VALUE] [--dry-run] [--checkpoint] [--quiet]");
        exit(2)
    )
    path = args[1]
    filters = Pair{String,String}[]
    dry = false
    checkpoint = false
    quiet = false
    i = 2
    while i <= length(args)
        a = args[i]
        if a == "--only"
            i += 1
            i <= length(args) || error("--only needs KEY=VALUE")
            kv = split(args[i], "="; limit=2)
            length(kv) == 2 || error("--only needs KEY=VALUE, got $(args[i])")
            push!(filters, String(kv[1]) => String(kv[2]))
        elseif a == "--dry-run"
            dry = true
        elseif a == "--checkpoint"
            checkpoint = true
        elseif a == "--quiet"
            quiet = true
        else
            error("unknown option $a")
        end
        i += 1
    end

    configs = load_experiments(path)
    function keep(cfg)
        all(filters) do (k, v)
            if k == "tag"
                cfg.tag == v
            elseif k == "constraint"
                String(cfg.constraint) == v
            elseif k == "threshold"
                cfg.threshold == parse(Float64, v)
            elseif k == "seed"
                cfg.seed == parse(Int, v)
            else
                error("--only supports tag, constraint, threshold and seed (got $k)")
            end
        end
    end
    configs = filter(keep, configs)
    isempty(configs) && error("no experiment in $path matches the filters")

    println("$(length(configs)) experiment(s) from $path, $(Threads.nthreads()) thread(s)")
    for cfg in configs
        if dry
            small = with_overrides(
                cfg; n_sample=min(cfg.n_sample, 200), n_per_chunk=min(cfg.n_per_chunk, 200), time_center_from=nothing
            )
            res = run_precalibration(small; verbose=false)
            println(
                "  [dry run] $(cfg.tag): configuration valid; $(n_accepted(res)) of $(res.n_simulated) test simulations accepted",
            )
            continue
        end
        dir = joinpath(cfg.output_dir, cfg.tag)
        ckpt = checkpoint ? joinpath(dir, "checkpoints") : nothing
        println("→ $(cfg.tag) (seed $(cfg.seed)) → $dir")
        res = run_precalibration(cfg; checkpoint_dir=ckpt, verbose=(!quiet))
        save_result(joinpath(dir, "result.jld2"), res)
        write_summary_csvs(dir, res)
        println("  $(n_accepted(res)) accepted of $(res.n_simulated) simulated in $(res.provenance["wall_seconds"]) s")
    end
end

main(ARGS)
