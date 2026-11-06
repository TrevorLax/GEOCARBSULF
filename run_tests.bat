@echo off
rem Run the comparison with the original R/Fortran code and the Julia test suite.
rem Output goes to the logs folder, in files named with the date and time of the run
rem (for example logs\test_suite_20261030-154500.log), so a sync client never sees
rem two versions of the same file.
cd /d "%~dp0"
if not exist logs mkdir logs
set STAMP=
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set STAMP=%%i
if "%STAMP%"=="" set STAMP=run
echo Logs: logs\*_%STAMP%.log
echo [1/3] Installing Julia dependencies (first run only, a few minutes)...
julia --project=. -e "using Pkg; Pkg.instantiate(); Pkg.precompile()" > logs\instantiate_%STAMP%.log 2>&1
echo [2/3] Comparing with the original R/Fortran code...
julia --project=. test\legacy_comparison\run_comparison.jl > logs\legacy_comparison_%STAMP%.log 2>&1
echo [3/3] Running the test suite...
julia --project=. -e "using Pkg; Pkg.test()" > logs\test_suite_%STAMP%.log 2>&1
echo Done. Results are in the logs folder (files ending in _%STAMP%.log).
pause
