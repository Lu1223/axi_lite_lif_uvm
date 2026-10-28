@echo off
setlocal
title UVM AXI-Lite LIF Reg Test - One-Click Runner

REM ============================================================
REM  One-click UVM test runner (ModelSim ASE + UVM 1.2 from source)
REM  Step 1: compile UVM library once (cached in uvm_lib, 1-2 min first time)
REM  Step 2: compile DUT
REM  Step 3: compile UVM testbench
REM  Step 4: run simulation, dump waveform, show result
REM  NOTE: this file must stay ASCII-only (cmd parses bat as GBK)
REM ============================================================

REM --- Tool paths (edit here if ModelSim is installed elsewhere) ---
set "MSIM=D:\LenovoSoftstore\Install\intelFPGA_lite\17.1\modelsim_ase\win32aloem"
set "UVM_SRC=D:\LenovoSoftstore\Install\intelFPGA_lite\17.1\modelsim_ase\verilog_src\uvm-1.2\src"

REM --- Make ModelSim available in this window ---
set "PATH=%MSIM%;%PATH%"
cd /d "%~dp0"

echo.
echo ============================================
echo  [Step 1/4] UVM library
echo ============================================
if not exist "uvm_lib\_info" (
    echo First run: compiling UVM 1.2 from source, please wait 1-2 minutes...
    vlib uvm_lib
    if errorlevel 1 goto :fail
    vlog -sv -work uvm_lib +incdir+%UVM_SRC% %UVM_SRC%\uvm_pkg.sv +define+UVM_NO_DPI
    if errorlevel 1 goto :fail
    echo UVM library compiled and cached.
) else (
    echo UVM library already cached, skip.
)

echo.
echo ============================================
echo  [Step 2/4] Compile DUT
echo ============================================
if exist work rmdir /s /q work
vlib work
vlog -sv -work work -timescale 1ns/1ps -L uvm_lib ..\rtl\design.sv
if errorlevel 1 goto :fail

echo.
echo ============================================
echo  [Step 3/4] Compile UVM testbench
echo ============================================
vlog -sv -work work -timescale 1ns/1ps -L uvm_lib +incdir+%UVM_SRC% ..\tb\testbench.sv
if errorlevel 1 goto :fail

echo.
echo ============================================
echo  [Step 4/4] Run simulation (dump waveform to wave\sim.wlf)
echo ============================================
vsim -c -L uvm_lib -wlf wave\sim.wlf work.uvm_test_top -do scripts\run.do -l logs\sim_log.txt
if errorlevel 1 goto :fail

echo.
echo ============================================
echo  RESULT
echo ============================================
findstr /C:"[PASS]" /C:"[FAIL]" /C:"RESULT" /C:"ALL TESTS" /C:"SOME TESTS" /C:"UVM_ERROR" /C:"UVM_FATAL" logs\sim_log.txt
echo.
echo Full log : %~dp0logs\sim_log.txt
echo Waveform : %~dp0wave\sim.wlf  (double-click run_wave.bat to view)
echo.
pause
exit /b 0

:fail
echo.
echo *** FAILED - check the error messages above ***
echo.
pause
exit /b 1
