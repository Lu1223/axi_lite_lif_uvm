@echo off
setlocal
title UVM Waveform Viewer

REM ============================================================
REM  Waveform viewer - opens sim.wlf dumped by run_uvm.bat
REM  (does NOT re-simulate; run run_uvm.bat first)
REM  NOTE: this file must stay ASCII-only (cmd parses bat as GBK)
REM ============================================================

set "MSIM=D:\LenovoSoftstore\Install\intelFPGA_lite\17.1\modelsim_ase\win32aloem"
set "PATH=%MSIM%;%PATH%"
cd /d "%~dp0"

if not exist "wave\sim.wlf" (
    echo wave\sim.wlf not found. Run run_uvm.bat first to dump the waveform.
    pause
    exit /b 1
)

vsim -gui -view wave\sim.wlf -do scripts\wave_view.do
