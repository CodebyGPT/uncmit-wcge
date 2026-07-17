#requires -version 7
# uncmit.ps1 - Interactive GUI to strip CMIT closed-source components from
# a Windows 10 wcge install.wim by replacing 6 deployment exes with de-CMIT builds.
#
# Usage:
#   Run in PowerShell 7 as Administrator.
#   Select the original install.wim (e.g. from a wcge ISO sources\ folder),
#   the script mounts it, replaces the 6 CMIT deployment exes with the
#   de-CMIT versions shipped alongside this script, commits, and unmounts.
#
# No Chinese characters in this file by design (ASCII-only UI strings).

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Must run in PowerShell 7 and as Administrator (dism requires elevation)
# ---------------------------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 7) {
    [System.Windows.Forms.MessageBox]::Show("PowerShell 7 or newer is required. Current version: $($PSVersionTable.PSVersion).", "Error", "OK", "Error")
    exit 1
}

$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.Forms.MessageBox]::Show("This script must be run as Administrator (dism requires elevation). Right-click and 'Run with PowerShell' as admin.", "Error", "OK", "Error")
    exit 1
}

# ---------------------------------------------------------------------------
# Paths: 6 CMIT deployment exes inside the WIM (relative to mount root)
# Source = de-CMIT builds. Prefer a local dist\ folder (offline/dev use); if
# absent, auto-download from the project's GitHub raw URL at runtime.
# ---------------------------------------------------------------------------
# When run via `irm ... | iex`, $MyInvocation.MyCommand.Definition is empty.
# Treat empty/absent script dir as "no local dist\" -> download at runtime.
$ScriptDef = $MyInvocation.MyCommand.Definition
$ScriptDir = if ($ScriptDef) { Split-Path -Parent $ScriptDef } else { "" }
$RemoteBase = "https://raw.githubusercontent.com/CodebyGPT/uncmit-wcge/master/dist"

if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir "dist"))) {
    $DistDir = Join-Path $ScriptDir "dist"
} elseif ($ScriptDir -and (Test-Path (Join-Path $ScriptDir "..\dist"))) {
    $DistDir = Resolve-Path (Join-Path $ScriptDir "..\dist")
} else {
    # No local dist\: download on the fly into a temp folder.
    $DistDir = Join-Path $env:TEMP ("uncmit-dist-" + [guid]::NewGuid().ToString("N").Substring(0,8))
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
    $DownloadNeeded = $true
}

function Get-DeCMITBuilds($dir, $base) {
    $names = @("InsPreConfig","InsPostConfig","UpgradeConfig","UpgradeSchdTask","ResetPreConfig","ResetPostConfig")
    foreach ($n in $names) {
        $url = "$base/$n.exe"
        $out = Join-Path $dir "$n.exe"
        Log "Downloading $n.exe ..."
        try {
            Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
        } catch {
            Log "ERROR: failed to download $url : $_"
            return $false
        }
    }
    return $true
}

$ReplaceMap = @(
    @{ WimPath = "Windows\Temp\InsPreConfig.exe";          Src = "InsPreConfig.exe" }
    @{ WimPath = "Windows\Temp\InsPostConfig.exe";         Src = "InsPostConfig.exe" }
    @{ WimPath = "Windows\Temp\UpgradeConfig.exe";         Src = "UpgradeConfig.exe" }
    @{ WimPath = "Windows\Temp\UpgradeSchdTask.exe";       Src = "UpgradeSchdTask.exe" }
    @{ WimPath = "Windows\Temp\Recovery\OEM\CMGE\ResetSources\ResetPreConfig.exe";  Src = "ResetPreConfig.exe" }
    @{ WimPath = "Windows\Temp\Recovery\OEM\CMGE\ResetSources\ResetPostConfig.exe"; Src = "ResetPostConfig.exe" }
)

# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
$form = [System.Windows.Forms.Form]::new()
$form.Text = "uncmit - Strip CMIT components from install.wim"
$form.Size = [System.Drawing.Size]::new(640, 420)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$lblWim = [System.Windows.Forms.Label]::new()
$lblWim.Location = [System.Drawing.Point]::new(12, 15)
$lblWim.Size = [System.Drawing.Size]::new(80, 20)
$lblWim.Text = "install.wim:"
$form.Controls.Add($lblWim)

$txtWim = [System.Windows.Forms.TextBox]::new()
$txtWim.Location = [System.Drawing.Point]::new(100, 12)
$txtWim.Size = [System.Drawing.Size]::new(420, 20)
$txtWim.ReadOnly = $true
$form.Controls.Add($txtWim)

$btnBrowse = [System.Windows.Forms.Button]::new()
$btnBrowse.Location = [System.Drawing.Point]::new(530, 10)
$btnBrowse.Size = [System.Drawing.Size]::new(90, 23)
$btnBrowse.Text = "Browse..."
$form.Controls.Add($btnBrowse)

$btnRun = [System.Windows.Forms.Button]::new()
$btnRun.Location = [System.Drawing.Point]::new(530, 40)
$btnRun.Size = [System.Drawing.Size]::new(90, 28)
$btnRun.Text = "Run"
$btnRun.Enabled = $false
$form.Controls.Add($btnRun)

$logBox = [System.Windows.Forms.TextBox]::new()
$logBox.Location = [System.Drawing.Point]::new(12, 80)
$logBox.Size = [Size]::new(608, 300)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::Black
$logBox.ForeColor = [System.Drawing.Color]::LightGreen
$logBox.Font = [System.Drawing.Font]::new("Consolas", 9)
$form.Controls.Add($logBox)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
$mountDir = $null

function Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$ts] $msg`r`n")
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Find-Dism {
    $d = Get-Command dism.exe -ErrorAction SilentlyContinue
    if (-not $d) {
        Log "ERROR: dism.exe not found in PATH. Install Windows ADK or run on Windows 10/11."
        return $null
    }
    return $d.Source
}

function Mount-Wim($wim, $dir) {
    Log "Mounting WIM (read-write) to $dir ..."
    $out = & dism.exe /Mount-Image /ImageFile:"$wim" /Index:1 /MountDir:"$dir" 2>&1
    $out | ForEach-Object { Log $_ }
    if ($LASTEXITCODE -ne 0) {
        Log "ERROR: Mount failed (exit $LASTEXITCODE)."
        return $false
    }
    Log "Mount OK."
    return $true
}

function Replace-Exes($dir) {
    $ok = $true
    foreach ($m in $ReplaceMap) {
        $src = Join-Path $DistDir $m.Src
        $dst = Join-Path $dir $m.WimPath
        if (-not (Test-Path $src)) {
            Log "ERROR: missing de-CMIT build: $src"
            $ok = $false
            continue
        }
        if (-not (Test-Path $dst)) {
            Log "WARN: target not found in WIM (already absent?): $($m.WimPath)"
            continue
        }
        try {
            Copy-Item -Path $src -Destination $dst -Force
            Log "Replaced: $($m.WimPath)"
        } catch {
            Log "ERROR: failed to replace $($m.WimPath): $_"
            $ok = $false
        }
    }
    return $ok
}

function Commit-Wim($dir) {
    Log "Committing and unmounting WIM ..."
    $out = & dism.exe /Unmount-Wim /MountDir:"$dir" /Commit 2>&1
    $out | ForEach-Object { Log $_ }
    if ($LASTEXITCODE -ne 0) {
        Log "ERROR: Commit failed (exit $LASTEXITCODE). WIM left mounted at $dir."
        return $false
    }
    Log "Commit OK. install.wim updated."
    return $true
}

function Discard-Wim($dir) {
    Log "Discarding and unmounting WIM (no changes saved) ..."
    & dism.exe /Unmount-Wim /MountDir:"$dir" /Discard 2>&1 | ForEach-Object { Log $_ }
}

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------
$btnBrowse.Add_Click({
    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Filter = "WIM image (*.wim)|*.wim|All files (*.*)|*.*"
    $dlg.Title = "Select original install.wim"
    if ($dlg.ShowDialog() -eq "OK") {
        $txtWim.Text = $dlg.FileName
        $btnRun.Enabled = $true
    }
})

$btnRun.Add_Click({
    $btnRun.Enabled = $false
    $btnBrowse.Enabled = $false
    $wim = $txtWim.Text

    if (-not (Test-Path $wim)) {
        Log "ERROR: WIM path not found: $wim"
        $btnRun.Enabled = $true; $btnBrowse.Enabled = $true
        return
    }
    if ($DownloadNeeded) {
        if (-not (Get-DeCMITBuilds $DistDir $RemoteBase)) {
            Log "ERROR: could not download de-CMIT builds. Check network and GitHub reachability."
            $btnRun.Enabled = $true; $btnBrowse.Enabled = $true
            return
        }
    } elseif (-not (Test-Path $DistDir)) {
        Log "ERROR: dist\ folder not found next to this script: $DistDir"
        $btnRun.Enabled = $true; $btnBrowse.Enabled = $true
        return
    }

    $dism = Find-Dism
    if (-not $dism) {
        $btnRun.Enabled = $true; $btnBrowse.Enabled = $true
        return
    }

    $mountDir = Join-Path $env:TEMP ("uncmit-mount-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Path $mountDir -Force | Out-Null

    try {
        if (-not (Mount-Wim $wim $mountDir)) { throw "mount failed" }
        if (-not (Replace-Exes $mountDir)) { throw "replace failed" }
        if (-not (Commit-Wim $mountDir)) { throw "commit failed" }
        Log "DONE. The selected install.wim now contains de-CMIT deployment exes."
        Log "Next: burn the modified ISO/USB with Rufus and install normally."
    } catch {
        Log "FAILED: $_"
        if ($mountDir -and (Test-Path $mountDir)) {
            Discard-Wim $mountDir
        }
    } finally {
        if ($mountDir -and (Test-Path $mountDir)) {
            try { Remove-Item -Recurse -Force $mountDir -ErrorAction SilentlyContinue } catch {}
        }
        $btnRun.Enabled = $true; $btnBrowse.Enabled = $true
    }
})

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
