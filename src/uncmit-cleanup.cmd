@echo off
setlocal enabledelayedexpansion

title uncmit-cleanup -- Stripping CMIT dead payload

echo === uncmit-cleanup v1.0 ===
echo Surgically removing CMIT closed-source dead payload
echo.

:: ---- Privilege check ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: This script must be run as Administrator.
    echo Right-click ^> Run as administrator.
    echo.
    pause
    exit /b 1
)

set ok=0
set warn=0

goto :main

:: ---- Subroutines ----

:log_ok
set /a ok+=1
echo [OK] %*
exit /b 0

:log_warn
set /a warn+=1
echo [WARN] %*
exit /b 0

:log_skip
echo [SKIP] %*
exit /b 0

:rm_dir
if exist "%~1" (
    rmdir /s /q "%~1" 2>nul
    if exist "%~1" (call :log_warn "%~2 -- could not remove") else call :log_ok "%~2"
) else call :log_skip "%~2 -- not found"
exit /b 0

:rm_file
if exist "%~1" (
    del /f /q "%~1" 2>nul
    call :log_ok "%~2"
) else call :log_skip "%~2 -- not found"
exit /b 0

:: =====================================================
:: Main
:: =====================================================
:main

echo.
echo === SECTION 1: CMIT Program Files ===

call :rm_dir "%SystemDrive%\Program Files\CMITActivation"         "CMITActivation"
call :rm_dir "%SystemDrive%\Program Files\CMITControlCenter"      "CMITControlCenter"
call :rm_dir "%SystemDrive%\Program Files\CmitUpdateAgent"        "CmitUpdateAgent"
call :rm_dir "%SystemDrive%\Program Files\CMITOfflineUpdateInstaller" "CMITOfflineUpdateInstaller"
call :rm_dir "%SystemDrive%\Program Files\CMIT3.0"                "CMIT3.0"

echo.
echo === SECTION 2: CMIT Recovery/Reset Payload ===

set _rb=%SystemDrive%\Recovery\OEM\CMGE\ResetSources

if exist "%_rb%" (
    call :rm_dir "%_rb%\CMITActivation"             "Recovery\CMITActivation"
    call :rm_dir "%_rb%\CMITControlCenter"          "Recovery\CMITControlCenter"
    call :rm_dir "%_rb%\CmitUpdateAgent"            "Recovery\CmitUpdateAgent"
    call :rm_dir "%_rb%\CMITOfflineUpdateInstaller" "Recovery\CMITOfflineUpdateInstaller"
    call :rm_dir "%_rb%\CMITSMx"                    "Recovery\CMITSMx"
    call :rm_dir "%_rb%\SMxCNG"                     "Recovery\SMxCNG"
    call :rm_dir "%_rb%\CMGEInstaller"              "Recovery\CMGEInstaller"
    call :rm_dir "%_rb%\Certificates"               "Recovery\Certificates"
    call :rm_dir "%_rb%\GP_CMIT"                    "Recovery\GP_CMIT"
    call :rm_file "%_rb%\EPrivilege.exe"            "Recovery\EPrivilege.exe"
) else call :log_skip "Recovery partition not found at %_rb%"

:: Temp deployment leftovers
call :rm_dir "%windir%\Temp\Recovery\OEM\CMGE\ResetSources\CMITActivation"             "Temp\Recovery\CMITActivation"
call :rm_dir "%windir%\Temp\Recovery\OEM\CMGE\ResetSources\CMITControlCenter"          "Temp\Recovery\CMITControlCenter"
call :rm_dir "%windir%\Temp\Recovery\OEM\CMGE\ResetSources\CmitUpdateAgent"            "Temp\Recovery\CmitUpdateAgent"
call :rm_dir "%windir%\Temp\Recovery\OEM\CMGE\ResetSources\CMITOfflineUpdateInstaller" "Temp\Recovery\CMITOfflineUpdateInstaller"
call :rm_dir "%windir%\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx"                    "Temp\Recovery\CMITSMx"
call :rm_dir "%windir%\Temp\Recovery\OEM\CMGE\ResetSources\CMGEInstaller"              "Temp\Recovery\CMGEInstaller"
call :rm_dir "%windir%\Temp\CMITActivation"         "Temp\CMITActivation"
call :rm_dir "%windir%\Temp\CMITControlCenter"      "Temp\CMITControlCenter"
call :rm_dir "%windir%\Temp\CmitUpdateAgent"        "Temp\CmitUpdateAgent"


echo === SECTION 3: Temp Deployment Files ===

call :rm_file "%windir%\Temp\UpgradeConfig.exe"         "Temp\UpgradeConfig.exe"
call :rm_file "%windir%\Temp\UpgradeSchdTask.exe"       "Temp\UpgradeSchdTask.exe"
call :rm_file "%windir%\Temp\InsPreConfig.exe"          "Temp\InsPreConfig.exe"
call :rm_file "%windir%\Temp\InsPostConfig.exe"         "Temp\InsPostConfig.exe"
call :rm_file "%windir%\Temp\SetupComplete.cmd"         "Temp\SetupComplete.cmd"
call :rm_file "%windir%\Temp\InsPreConfigPS.ps1"        "Temp\InsPreConfigPS.ps1"
call :rm_file "%windir%\Temp\InsPostConfigPS.ps1"       "Temp\InsPostConfigPS.ps1"

:: Remove %windir%\Setup\Scripts if empty
if exist "%windir%\Setup\Scripts" (
    dir "%windir%\Setup\Scripts" /b >nul 2>nul
    if errorlevel 1 (
        rmdir "%windir%\Setup\Scripts" >nul 2>nul
        call :log_ok "Removed empty: Setup\Scripts"
    )
)

:: ===== Summary =====
echo.
echo ========================================
echo   uncmit-cleanup complete
echo   %ok% items removed / confirmed clean
if %warn% gtr 0 echo   %warn% warnings (see log above)
echo ========================================
echo.
echo Reboot recommended to finalize changes.
echo.
pause
exit /b 0