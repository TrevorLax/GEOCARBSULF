# capture_env.jl: record the machine and software a session ran on (plan §6.1, §7), as
# env.toml in the results folder. Included by run_timing.jl.
#
# Antivirus (decision T6, option A): real-time protection is left as it is, with no
# exclusions; its state is recorded so the report can show it. Exclusion lists are not
# read (they need administrator rights).

using SHA: sha256
using InteractiveUtils: versioninfo
using LinearAlgebra: BLAS

function _cmd_output(cmd; default = "unavailable")
    try
        return strip(read(pipeline(ignorestatus(cmd); stderr = devnull), String))
    catch
        return default
    end
end
_ps(script) = _cmd_output(`powershell -NoProfile -NonInteractive -Command $script`)

function _sha(path)
    isfile(path) || return "missing"
    return bytes2hex(open(sha256, path))
end

function capture_env(path::AbstractString; rscript, repo = REPO_DIR, results_root = "", legacy_libs = String[])
    env = Dict{String,Any}()
    env["host"] = gethostname()
    env["captured"] = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
    env["os"] = string(Sys.KERNEL, " ", Sys.MACHINE)
    ci = Sys.cpu_info()
    env["cpu_model"] = isempty(ci) ? "unknown" : strip(ci[1].model)
    env["logical_cores"] = Sys.CPU_THREADS
    env["ram_bytes"] = Int(Sys.total_memory())
    env["julia_version"] = string(VERSION)
    env["julia_versioninfo"] = sprint(io -> versioninfo(io; verbose = false))
    env["julia_threads"] = Threads.nthreads()
    env["blas_config"] = string(BLAS.get_config())
    env["results_root"] = results_root
    env["results_root_synced"] = is_synced_path(results_root)
    env["repo"] = repo
    env["repo_synced"] = is_synced_path(repo)
    env["git_commit"] = isdir(joinpath(repo, ".git")) ? _cmd_output(`git -C $repo rev-parse HEAD`) : "no .git folder"
    env["legacy_libraries"] = Dict(basename(l) => _sha(l) for l in legacy_libs)

    if Sys.iswindows()
        env["os_build"] = _ps("(Get-CimInstance Win32_OperatingSystem | ForEach-Object { \$_.Caption + ' ' + \$_.Version })")
        env["physical_cores"] = _ps("(Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum")
        env["power_scheme"] = _cmd_output(`powercfg /getactivescheme`)
        env["on_battery"] = _ps("if (Get-CimInstance Win32_Battery) { (Get-CimInstance Win32_Battery).BatteryStatus -ne 2 } else { 'no battery' }")
        env["disk_of_results"] = _ps("Get-Partition -DriveLetter '$(uppercase(first(results_root)))' | Get-Disk | Get-PhysicalDisk | Select-Object -ExpandProperty MediaType")
        av = Dict{String,Any}()
        av["products"] = _ps("Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | ForEach-Object { \$_.displayName + ' (state ' + \$_.productState + ')' }")
        av["defender_status"] = _ps("Get-MpComputerStatus | Select-Object RealTimeProtectionEnabled,AntivirusEnabled,AMEngineVersion,AntivirusSignatureVersion,QuickScanEndTime,FullScanEndTime | Format-List | Out-String")
        av["defender_scan_schedule"] = _ps("Get-MpPreference | Select-Object ScanScheduleDay,ScanScheduleTime,ScanScheduleQuickScanTime | Format-List | Out-String")
        av["policy"] = "T6 option A: real-time protection unchanged, no exclusions"
        env["antivirus"] = av
    else
        env["os_build"] = _cmd_output(`uname -a`)
        env["physical_cores"] = _cmd_output(`sh -c "lscpu -p=Core,Socket 2>/dev/null | grep -v '^#' | sort -u | wc -l"`)
        env["antivirus"] = Dict("policy" => "T6 option A: real-time protection unchanged, no exclusions",
                                "products" => "not recorded on this OS")
    end

    if rscript !== nothing
        rbin = joinpath(dirname(rscript), Sys.iswindows() ? "R.exe" : "R")
        env["r_session_info"] = _cmd_output(`$rscript -e "si <- sessionInfo(); print(si); cat('BLAS:', si\$BLAS, '\nLAPACK:', si\$LAPACK, '\n')"`)
        env["r_packages"] = _cmd_output(`$rscript -e "for (p in c('lhs','CholWishart','MASS','abind','Hmisc','bench','ps')) cat(p, if (requireNamespace(p, quietly=TRUE)) as.character(packageVersion(p)) else 'NOT INSTALLED', '\n')"`)
        env["r_fc"] = _cmd_output(`$rbin CMD config FC`)
        env["r_fflags"] = _cmd_output(`$rbin CMD config FFLAGS`)
        env["r_fcflags"] = _cmd_output(`$rbin CMD config FCFLAGS`)
        fc = split(env["r_fc"])
        env["gfortran_version"] = isempty(fc) ? "unknown" : _cmd_output(Cmd(vcat(String.(fc), ["--version"])))
    end
    open(io -> TOML.print(io, env; sorted = true), path, "w")
    return env
end
