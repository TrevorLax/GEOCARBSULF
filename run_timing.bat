@echo off
rem Timing benchmark of the original R/Fortran code and the Julia port
rem (TIMING_BENCHMARK_PLAN.md; details in benchmark\timing\README.md).
rem
rem   run_timing.bat                       quick suite (about 20-40 minutes)
rem   run_timing.bat --suite smoke         every part once with tiny sizes (checks the set-up)
rem   run_timing.bat --suite standard      2-3 hours
rem   run_timing.bat --suite full          overnight
rem   run_timing.bat --suite quick --only model,engine     selected parts
rem
rem Results are written OUTSIDE the synced folder, to
rem   %LOCALAPPDATA%\GeocarbTiming\<computer>_<date-time>\report.md
rem Close other programs, use mains power and the "Best performance" power mode.
cd /d "%~dp0"
if not exist logs mkdir logs
set STAMP=
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set STAMP=%%i
if "%STAMP%"=="" set STAMP=run
echo [1/2] Setting up the benchmark's Julia environment (first run: 10-20 minutes for CairoMakie)...
julia --project=. -e "using Pkg; Pkg.instantiate()" > logs\timing_instantiate_%STAMP%.log 2>&1
julia --project=benchmark\timing -e "using Pkg; Pkg.instantiate(); Pkg.precompile()" >> logs\timing_instantiate_%STAMP%.log 2>&1
if errorlevel 1 (
  echo Setting up failed; see logs\timing_instantiate_%STAMP%.log
  pause
  exit /b 1
)
echo [2/2] Running the benchmark (progress below; full logs go to the results folder)...
set ARGS=%*
if "%ARGS%"=="" set ARGS=--suite quick
julia --project=benchmark\timing benchmark\timing\run_timing.jl --install-r-packages %ARGS%
pause
