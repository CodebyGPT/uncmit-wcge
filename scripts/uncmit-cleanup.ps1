#requires -version 5.1
# uncmit-cleanup.ps1 — Post-install cleanup of CMIT closed‑source component files
#
# Run AFTER installing a uncmit‑patched wcge (Windows 10 神州网信政府版) image.
# This script surgically removes CMIT closed‑source binaries, certificates,
# services, scheduled tasks, and registry entries that may remain on disk
# as dead payload files.
#
# SAFEGUARDED: harmless CMIT customizations are NEVER touched:
#   • LGPO local group policies (privacy, telemetry, update blocking)
#   • Registry: Netlogon/wlidsvc disable, SettingsPageVisibility, NTP, KMS
#   • Brand strings ("神州网信政府版") and logo
#   • Disabled scheduled tasks (ScanForUpdates, ScanForUpdatesAsUser)
#   • Admin auto-logon secrets in unattend.xml (dead files in Recovery)
#   • LayoutModification.xml, logo.bmp
#
# Prerequisite: Run as Administrator
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\uncmit-cleanup.ps1

#Requires -RunAsAdministrator

$Host.UI.RawUI.WindowTitle = "uncmit-cleanup — Stripping CMIT dead payload"
$ErrorActionPreference = "Stop"

$log = @()
$ok  = 0
$warn = 0

function Log($text) {
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $text"
    $log += $line
    Write-Host $line
}

function LogOK($text) { Log "[OK] $text"; $ok++ }
function LogWarn($text) { Log "[WARN] $text"; $warn++ }
function LogSkip($text) { Log "[SKIP] $text" }

# ---------------------------------------------------------------------------
# Safety checks
# ---------------------------------------------------------------------------
Write-Host "=== uncmit-cleanup v1.0 ===" -ForegroundColor Cyan
Write-Host "Surgically removing CMIT closed-source dead payload" -ForegroundColor Cyan
Write-Host "Harmless CMIT customizations (LGPO, privacy reg keys, branding) are PRESERVED.`n" -ForegroundColor Yellow

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.1 or newer required." -ForegroundColor Red
    exit 1
}

$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# SECTION 1 — Stop and remove CMIT services
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 1: CMIT Services ===" -ForegroundColor Green

$cmitServices = @("CmitClientSVC", "CmitUpdateAgent")
foreach ($svc in $cmitServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            if ($s.Status -eq "Running") {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
            # Remove using sc.exe for clean unregister
            & sc.exe delete $svc 2>&1 | Out-Null
            # Also remove registry service key as fallback
            $svcKey = "HKLM:\SYSTEM\CurrentControlSet\services\$svc"
            if (Test-Path $svcKey) {
                Remove-Item -Path $svcKey -Recurse -Force -ErrorAction SilentlyContinue
            }
            LogOK "Removed service: $svc"
        } else {
            LogSkip "Service not found: $svc"
        }
    } catch {
        LogWarn "Could not remove service $svc : $_"
    }
}

# ---------------------------------------------------------------------------
# SECTION 2 — Remove CMIT scheduled tasks
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 2: CMIT Scheduled Tasks ===" -ForegroundColor Green

$cmitTasks = @(
    @{TaskPath = "\CMIT\CmitUpdateAgent\"; TaskName = "CmitUpdateAgent Daily Runner"}
)
foreach ($t in $cmitTasks) {
    try {
        $fullName = $t.TaskPath + $t.TaskName
        $existing = Get-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
            LogOK "Removed scheduled task: $fullName"
        } else {
            LogSkip "Scheduled task not found: $fullName"
        }
    } catch {
        LogWarn "Could not remove scheduled task $($t.TaskName) : $_"
    }
}

# Also remove the \CMIT\ folder if empty after task removal
try {
    $cmitFolder = Get-ScheduledTask -TaskPath "\CMIT\" -ErrorAction SilentlyContinue
    if (-not $cmitFolder) {
        # Folder exists but empty — schtasks.exe /delete for the folder
        & schtasks.exe /Delete /TN "\CMIT\CmitUpdateAgent" /F 2>&1 | Out-Null
    }
} catch {}

# ---------------------------------------------------------------------------
# SECTION 3 — Remove CMIT directories from Program Files
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 3: CMIT Program Files ===" -ForegroundColor Green

$pfDirs = @(
    "$env:SystemDrive\Program Files\CMITActivation",
    "$env:SystemDrive\Program Files\CMITControlCenter",
    "$env:SystemDrive\Program Files\CmitUpdateAgent",
    "$env:SystemDrive\Program Files\CMITOfflineUpdateInstaller",
    "$env:SystemDrive\Program Files\CMIT3.0"
)

foreach ($d in $pfDirs) {
    try {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $d) {
                # Some files might be in use; try takeown + icacls then retry
                try {
                    & takeown.exe /f $d /r /d Y 2>&1 | Out-Null
                    & icacls.exe $d /grant Administrators:F /T /Q 2>&1 | Out-Null
                    Remove-Item -Path $d -Recurse -Force -ErrorAction SilentlyContinue
                } catch {}
                if (Test-Path $d) {
                    LogWarn "Could not fully remove $d (files may be in use)"
                } else {
                    LogOK "Removed: $d"
                }
            } else {
                LogOK "Removed: $d"
            }
        } else {
            LogSkip "Not found: $d"
        }
    } catch {
        LogWarn "Could not remove $d : $_"
    }
}

# ---------------------------------------------------------------------------
# SECTION 4 — Remove CMIT payload from Recovery partition
#            (Keep: LGPO\, logo.bmp, LayoutModification.xml, ResetPre/Post*.exe)
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 4: CMIT Recovery/Reset Payload ===" -ForegroundColor Green

$recoveryBase = "$env:SystemDrive\Recovery\OEM\CMGE\ResetSources"

if (Test-Path $recoveryBase) {
    # Directories to DELETE (CMIT closed-source payload)
    $rmDirs = @(
        "CMITActivation",
        "CMITControlCenter",
        "CmitUpdateAgent",
        "CMITOfflineUpdateInstaller",
        "CMITSMx",
        "SMxCNG",
        "CMGEInstaller",
        "Certificates",
        "GP_CMIT"
    )
    foreach ($rd in $rmDirs) {
        $full = Join-Path $recoveryBase $rd
        try {
            if (Test-Path $full) {
                Remove-Item -Path $full -Recurse -Force -ErrorAction SilentlyContinue
                LogOK "Removed recovery payload: $rd"
            } else {
                LogSkip "Not found in recovery: $rd"
            }
        } catch {
            LogWarn "Could not remove $full : $_"
        }
    }

    # Files to DELETE (CMIT-specific)
    $rmFiles = @(
        "EPrivilege.exe"
    )
    foreach ($rf in $rmFiles) {
        $full = Join-Path $recoveryBase $rf
        try {
            if (Test-Path $full) {
                Remove-Item -Path $full -Force -ErrorAction SilentlyContinue
                LogOK "Removed recovery payload: $rf"
            } else {
                LogSkip "Not found in recovery: $rf"
            }
        } catch {}
    }

    # PRESERVED (logged for transparency)
    $keepItems = @(
        "LGPO",
        "logo.bmp",
        "LayoutModification.xml",
        "ResetPreConfigPS.ps1",
        "ResetPostConfigPS.ps1",
        "ResetPreConfig.exe",
        "ResetPostConfig.exe"
    )
    LogSkip "Preserved recovery items (LGPO, branding, reset exes): $($keepItems -join ', ')"
} else {
    LogSkip "Recovery partition not found at $recoveryBase"
}

# Also check for old-style temp deployment leftovers
$tempDeploy = @(
    "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITActivation",
    "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITControlCenter",
    "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CmitUpdateAgent",
    "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITOfflineUpdateInstaller",
    "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMITSMx",
    "$env:windir\Temp\Recovery\OEM\CMGE\ResetSources\CMGEInstaller",
    "$env:windir\Temp\CMITActivation",
    "$env:windir\Temp\CMITControlCenter",
    "$env:windir\Temp\CmitUpdateAgent"
)
foreach ($td in $tempDeploy) {
    try {
        if (Test-Path $td) {
            Remove-Item -Path $td -Recurse -Force -ErrorAction SilentlyContinue
            LogOK "Removed temp deployment: $td"
        }
    } catch {}
}

# ---------------------------------------------------------------------------
# SECTION 5 — Remove CMIT certificates from system cert stores
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 5: CMIT Certificates ===" -ForegroundColor Green

$certTargets = @(
    # CMIT certificates (backdoor — always remove)
    @{Subject = "*CMIT Root Authority*"; Store = "Root"; Note = "CMIT Root Authority (backdoor)"},
    @{Subject = "*CMIT SubP*";          Store = "CA";  Note = "CMIT SubP (backdoor)"},
    @{Subject = "*CMIT signature*";     Store = "TrustedPublisher"; Note = "CMIT signature (backdoor)"},
    # Government CA certificates (privacy-first: clear all Chinese government/industry CAs)
    @{Subject = "*Beijing ROOT CA*";    Store = "Root"; Note = "Beijing ROOT CA"},
    @{Subject = "*BeiJing ROOT CA New*"; Store = "Root"; Note = "Beijing ROOT CA New"},
    @{Subject = "*Beijing GCA*";        Store = "Root"; Note = "Beijing GCA (may be in Root or CA)"},
    @{Subject = "*Beijing GCA New*";    Store = "CA";  Note = "Beijing GCA New"},
    @{Subject = "*BJCA*";              Store = "Root"; Note = "BJCA (may be in Root or CA)"},
    @{Subject = "*BJCA New*";          Store = "CA";  Note = "BJCA New"},
    @{Subject = "*CEGN_RCA*";          Store = "Root"; Note = "CEGN Root CA"},
    @{Subject = "*CEGN_OCA*";          Store = "Root"; Note = "CEGN OCA (may be in Root or CA)"},
    @{Subject = "*GDCA_ROOT_CA*";      Store = "Root"; Note = "GDCA Root CA"},
    @{Subject = "*GDCA_Guangdong*";    Store = "Root"; Note = "GDCA Guangdong CA"},
    @{Subject = "*GDCA Guangdong*";    Store = "Root"; Note = "GDCA Guangdong CA (alt)"},
    @{Subject = "*SHECA*";             Store = "Root"; Note = "SHECA"},
    @{Subject = "*UCA Root*";          Store = "Root"; Note = "UCA (CFCA) Root"},
    @{Subject = "*UCA ROOT*";          Store = "Root"; Note = "UCA ROOT"},
    @{Subject = "*OSCCA*";             Store = "Root"; Note = "OSCCA ROOTCA (expired 2025)"},
    @{Subject = "*ROOTCA*";            Store = "Root"; Note = "ROOTCA (OSCCA)"}
)

function Remove-CmitCert($storeName, $subjectFilter) {
    $storePath = "Cert:\LocalMachine\$storeName"
    try {
        $certs = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue | Where-Object {
            $_.Subject -like $subjectFilter -or $_.FriendlyName -like $subjectFilter
        }
        if (-not $certs) {
            return $false
        }
        foreach ($cert in $certs) {
            try {
                # Determine the store's full path
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store `
                    "\\", "LocalMachine"
                $store.Open("ReadWrite")
                $store.Remove($cert)
                $store.Close()
                LogOK "Removed certificate: $($cert.Subject) from $storeName"
            } catch {
                # Fallback: use Cert:\ provider Remove-Item
                try {
                    $certPath = "$storePath\$($cert.Thumbprint)"
                    Remove-Item -Path $certPath -DeleteKey -ErrorAction SilentlyContinue
                    LogOK "Removed certificate (fallback): $($cert.Subject) from $storeName"
                } catch {
                    LogWarn "Could not remove cert $($cert.Subject) : $_"
                }
            }
        }
        return $true
    } catch {
        return $false
    }
}

foreach ($ct in $certTargets) {
    # Try both the primary store and alternate stores for misplaced certs
    $found = Remove-CmitCert $ct.Store $ct.Subject
    if (-not $found -and $ct.Store -eq "Root") {
        # Try CA as fallback (original script sometimes misplaced certs)
        Remove-CmitCert "CA" $ct.Subject | Out-Null
    }
    if (-not $found -and $ct.Store -eq "CA") {
        Remove-CmitCert "Root" $ct.Subject | Out-Null
    }
}

# Note: DigiCert certificates are NOT touched — Windows 10 ships these
# natively via Microsoft Root Certificate Program (KB931125 / Windows Update).
LogSkip "DigiCert certificates preserved (shipped by Windows natively)"

# ---------------------------------------------------------------------------
# SECTION 6 — Remove CMIT registry remnants
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 6: CMIT Registry Remnants ===" -ForegroundColor Green

$regEntries = @(
    # ClipSVC activation redirect
    @{Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ClipSVC";
      Name = "AltActivationClient"; Note = "ClipSVC → CmitClient redirect"},
    # DelayedAutostart for CmitClientSVC (if service key still exists)
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\services\CmitClientSVC";
      Name = "DelayedAutostart"; Note = "CmitClientSVC delayed autostart"},
    # CMIT MSI uninstall GUIDs (old activation tool versions)
    @{Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{61F90E65-243E-4FDB-9D44-E25D5C310F6F}";
      Name = $null; Note = "CMIT activation GUID 1"},
    @{Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{7D68C596-8427-4298-A288-7370D84C0F7A}";
      Name = $null; Note = "CMIT activation GUID 2"},
    @{Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{17A2CCB1-99E3-42D2-8085-43E05816C681}";
      Name = $null; Note = "CMIT activation GUID 3"},
    @{Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{6E2FB2CF-C8B2-47FC-846B-033BE3B81901}";
      Name = $null; Note = "CMIT activation GUID 4"}
)

foreach ($re in $regEntries) {
    try {
        if ($re.Name) {
            # Remove a specific value
            if (Test-Path $re.Path) {
                $existing = Get-ItemProperty -Path $re.Path -Name $re.Name -ErrorAction SilentlyContinue
                if ($existing -ne $null) {
                    Remove-ItemProperty -Path $re.Path -Name $re.Name -Force -ErrorAction SilentlyContinue
                    LogOK "Removed registry value: $($re.Path)\$($re.Name) ($($re.Note))"
                } else {
                    LogSkip "Registry value not found: $($re.Path)\$($re.Name)"
                }
            } else {
                LogSkip "Registry path not found: $($re.Path)"
            }
        } else {
            # Remove an entire key
            if (Test-Path $re.Path) {
                Remove-Item -Path $re.Path -Recurse -Force -ErrorAction SilentlyContinue
                LogOK "Removed registry key: $($re.Path) ($($re.Note))"
            } else {
                LogSkip "Registry key not found: $($re.Path)"
            }
        }
    } catch {
        LogWarn "Could not remove registry $($re.Path) : $_"
    }
}

# ---------------------------------------------------------------------------
# SECTION 7 — Remove CMIT KeyHolder from ClipSVC
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 7: CMIT KeyHolder ===" -ForegroundColor Green

$keyHolder = "$env:SystemDrive\ProgramData\Microsoft\Windows\ClipSVC\Install\KeyHolder"
try {
    if (Test-Path $keyHolder) {
        Remove-Item -Path $keyHolder -Recurse -Force -ErrorAction SilentlyContinue
        LogOK "Removed KeyHolder: $keyHolder"
    } else {
        LogSkip "KeyHolder not found"
    }
} catch {
    LogWarn "Could not remove KeyHolder : $_"
}

# ---------------------------------------------------------------------------
# SECTION 8 — Remove CMIT shortcuts
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 8: CMIT Shortcuts ===" -ForegroundColor Green

$shortcuts = @(
    "$env:Public\Desktop\控制中心.lnk",
    "$env:Public\Desktop\系统激活.lnk",
    "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\更新客户端",
    "$env:SystemDrive\ProgramData\Microsoft\Windows\Start Menu\Programs\CMGE控制中心"
)

foreach ($s in $shortcuts) {
    try {
        if (Test-Path $s) {
            if ((Get-Item $s) -is [System.IO.DirectoryInfo]) {
                Remove-Item -Path $s -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Remove-Item -Path $s -Force -ErrorAction SilentlyContinue
            }
            LogOK "Removed shortcut: $s"
        } else {
            LogSkip "Shortcut not found: $s"
        }
    } catch {}
}

# ---------------------------------------------------------------------------
# SECTION 9 — Remove CMIT deployment exe leftovers in Temp
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 9: Temp Deployment Files ===" -ForegroundColor Green

$tempFiles = @(
    "$env:windir\Temp\UpgradeConfig.exe",
    "$env:windir\Temp\UpgradeSchdTask.exe",
    "$env:windir\Temp\InsPreConfig.exe",
    "$env:windir\Temp\InsPostConfig.exe",
    "$env:windir\Temp\SetupComplete.cmd",
    "$env:windir\Temp\InsPreConfigPS.ps1",
    "$env:windir\Temp\InsPostConfigPS.ps1"
)
foreach ($tf in $tempFiles) {
    try {
        if (Test-Path $tf) {
            Remove-Item -Path $tf -Force -ErrorAction SilentlyContinue
            LogOK "Removed temp file: $tf"
        }
    } catch {}
}

# Also clean up %windir%\Setup\Scripts if it contains only CMIT scripts
$setupScripts = "$env:windir\Setup\Scripts"
try {
    if (Test-Path $setupScripts) {
        $scripts = Get-ChildItem -Path $setupScripts -ErrorAction SilentlyContinue
        if ($scripts.Count -eq 0) {
            Remove-Item -Path $setupScripts -Force -ErrorAction SilentlyContinue
            LogOK "Removed empty: $setupScripts"
        }
    }
} catch {}

# ---------------------------------------------------------------------------
# SECTION 10 — Cleanup CMIT SiPolicy (if left from original install)
# ---------------------------------------------------------------------------
Write-Host "`n=== SECTION 10: CMIT Code Integrity Policy ===" -ForegroundColor Green

$siPolicy = "C:\SiPolicy"
try {
    if (Test-Path $siPolicy) {
        Remove-Item -Path $siPolicy -Recurse -Force -ErrorAction SilentlyContinue
        LogOK "Removed: $siPolicy"
    } else {
        LogSkip "SiPolicy not found"
    }
} catch {
    LogWarn "Could not remove SiPolicy : $_"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n" -NoNewline
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  uncmit-cleanup complete" -ForegroundColor Cyan
Write-Host "  $ok items removed / confirmed clean" -ForegroundColor Green
if ($warn -gt 0) {
    Write-Host "  $warn warnings (see log above)" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nHarmless CMIT customizations PRESERVED:" -ForegroundColor Yellow
Write-Host "  • LGPO group policies (privacy, telemetry, update blocking)" -ForegroundColor Yellow
Write-Host "  • Registry: Netlogon/wlidsvc disable, SettingsPageVisibility" -ForegroundColor Yellow
Write-Host "  • Brand strings (神州网信政府版) and logo" -ForegroundColor Yellow
Write-Host "  • NTP config (cn.pool.ntp.org) and KMS server address" -ForegroundColor Yellow
Write-Host "  • Disabled Update scan tasks (ScanForUpdates)" -ForegroundColor Yellow
Write-Host "  • Recovery LGPO assets (Reset this PC policy preservation)" -ForegroundColor Yellow

Write-Host "`nReboot recommended to finalize service/task changes.`n" -ForegroundColor Gray
