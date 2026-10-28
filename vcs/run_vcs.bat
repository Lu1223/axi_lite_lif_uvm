@echo off
setlocal
title VCS UVM AXI-Lite Test - VM One-Click Runner

REM ============================================================
REM  One-click VCS + UVM runner (executes on VM via SSH)
REM  VM  : VCS_xianyu (RHEL 8.10)  user yian  192.168.36.100
REM  Flow: compile - 5 UVM tests - sync logs back to Windows
REM  NOTE: this file must stay ASCII-only (cmd parses bat as GBK)
REM ============================================================

set "VM_USER=yian"
set "VM_HOST=192.168.36.100"
set "KEY=%USERPROFILE%\.ssh\vm_ubuntu1_key"

REM --- Pre-checks -------------------------------------------------
where ssh >nul 2>nul
if errorlevel 1 (
    echo [ERROR] OpenSSH client not found.
    echo         Install: Settings - Apps - Optional features - OpenSSH Client
    pause
    exit /b 1
)
if not exist "%KEY%" (
    echo [ERROR] SSH key not found: %KEY%
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Connectivity check : %VM_HOST%
echo ============================================
ssh -i "%KEY%" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new %VM_USER%@%VM_HOST% "echo VM OK - && hostname && ls /mnt/hgfs/Code_total > /dev/null && echo hgfs share OK"
if errorlevel 1 (
    echo.
    echo [ERROR] Cannot reach VM %VM_HOST%.
    echo         Check that VCS_xianyu is running in VMware.
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Step 1/3 : Compile (VCS -full64 + UVM 1.2)
echo ============================================
ssh -i "%KEY%" %VM_USER%@%VM_HOST% "cd ~/eda_sim/uvm_axi_sim && make compile"
if errorlevel 1 goto :fail

echo.
echo ============================================
echo  Step 2/3 : Run 5 UVM tests
echo ============================================
ssh -i "%KEY%" %VM_USER%@%VM_HOST% "cd ~/eda_sim/uvm_axi_sim && make run_all"
if errorlevel 1 goto :fail

echo.
echo ============================================
echo  Step 3/3 : Sync logs back to Windows
echo ============================================
ssh -i "%KEY%" %VM_USER%@%VM_HOST% "cd ~/eda_sim/uvm_axi_sim && make sync_logs && echo SYNC_OK"

echo.
echo ============================================
echo  RESULT
echo ============================================
ssh -i "%KEY%" %VM_USER%@%VM_HOST% "cd ~/eda_sim/uvm_axi_sim && for t in test_reset_default test_reg_rw test_ro_protect test_illegal_addr test_random_regression; do if grep -qE 'UVM_(ERROR|FATAL) *: *[1-9]' run_$t.log; then echo '>>> '$t' : FAIL'; else echo '>>> '$t' : PASS'; fi; done"
echo.
echo  Logs synced to : %~dp0sim\
echo.
pause
exit /b 0

:fail
echo.
echo *** FAILED - check the error messages above ***
echo.
pause
exit /b 1
