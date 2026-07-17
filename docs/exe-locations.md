# exe-locations.md — CMIT deployment exe paths and modification map

Source WIM: `H:\sources\install.wim` (Windows 10 wcge, build 19044.1415, CMGE V2022-L.1345.000)
Indexed via `wimlib-imagex dir` (120,936 entries). Extraction via `wimlib-imagex extract`
(no admin needed) + PS2EXE `-extract` to recover embedded PowerShell.

## 1. Six primary deployment exes (replace these in the image)

| # | WIM path | Size | Phase | extracted.ps1 |
|---|----------|------|-------|---------------|
| 1 | `Windows\Temp\InsPreConfig.exe` | — | specialize | `reverse/InsPreConfig.extracted.ps1` |
| 2 | `Windows\Temp\InsPostConfig.exe` | — | oobeSystem (first logon) | `reverse/InsPostConfig.extracted.ps1` |
| 3 | `Windows\Temp\UpgradeConfig.exe` | — | upgrade (SetupComplete.cmd when Windows.old) | `reverse/UpgradeConfig.extracted.ps1` |
| 4 | `Windows\Temp\UpgradeSchdTask.exe` | — | upgrade (task re-creation) | `reverse/UpgradeSchdTask.extracted.ps1` |
| 5 | `Windows\Temp\Recovery\OEM\CMGE\ResetSources\ResetPreConfig.exe` | 138928 | reset (pre) | `reverse/ResetPreConfig.extracted.ps1` |
| 6 | `Windows\Temp\Recovery\OEM\CMGE\ResetSources\ResetPostConfig.exe` | 84144 | reset (post) | `reverse/ResetPostConfig.extracted.ps1` |

NOTE: the `unattend.xml` in `Windows\Panther` calls `%windir%\Temp\InsPreConfigPS.ps1`
→ `InsPreConfig.exe` (path #1) and `InsPostConfigPS.ps1` → `InsPostConfig.exe` (path #2).
Replacing the exe body is sufficient; the launcher .ps1 and unattend.xml need NOT change.

## 2. Called closed-source binaries (DO NOT DELETE — only disable invocation)

Per decision: "only disable invocation, keep binaries as dead files."

| Binary | WIM path | Called by |
|--------|----------|-----------|
| `EPrivilege.exe` | `Windows\Temp\Recovery\OEM\CMGE\ResetSources\EPrivilege.exe` | UpgradeConfig, UpgradeSchdTask, ResetPreConfig, ResetPostConfig |
| `CMGEInstaller.exe` | `Windows\Temp\Recovery\OEM\CMGE\ResetSources\CMGEInstaller\CMGEInstaller.exe` | via EPrivilege in UpgradeConfig / Reset* |
| `CmitClient.exe` | `Program Files\CMITActivation\CmitClient.exe` + `ResetSources\CMITActivation\...\CmitClient.exe` | InsPreConfig (SMx), UpgradeConfig (ClipSVC redirect), ResetPreConfig |
| `CmitServiceMonitor.exe` | `Program Files\CmitUpdateAgent\CmitServiceMonitor.exe` + `ResetSources\CmitUpdateAgent\...` | InsPostConfig / ResetPostConfig (Daily Runner task action) |
| `Wst*Config.exe` (SMx, x10) | `ResetSources\CMITSMx\win32\` and `\win64\` | InsPreConfig, UpgradeConfig, UpgradeSchdTask, ResetPreConfig (国密 SMx register) |

## 3. Disable vs Preserve per exe

### InsPreConfig.exe (specialize)
DISABLE:
- Install CMITActivation / CMITControlCenter / CmitUpdateAgent / CMITOfflineUpdateInstaller
- Register CmitClientSVC service (via InstallUtil in InsPost, not here)
- Import CMIT Root Authority → Root; CMIT SubP → CA; CMIT signature → TrustedPublisher
- Import ALL certificate imports (DigiCert included — Win10 ships these by default)
- Register SMx crypto provider (Wst*Config.exe -register)
PRESERVE:
- LGPO.exe /g import
- Disable InstallService ScanForUpdates / ScanForUpdatesAsUser
- Netlogon Start=4, wlidsvc disable
- Telemetry/privacy registry
- robocopy Recovery → SystemDrive\Recovery; hide C:\Recovery

### InsPostConfig.exe (oobe first logon)
DISABLE:
- InstallUtil CmitClientSVC.exe + DelayedAutostart
- Register-ScheduledTask "\CMIT\CmitUpdateAgent\CmitUpdateAgent Daily Runner" (CmitServiceMonitor.exe, Id 10086)
- Import CMIT certs (if any)
PRESERVE:
- Disable InstallService ScanForUpdates / ScanForUpdatesAsUser
- LayoutModification / logo deploy (if present)

### UpgradeConfig.exe (upgrade)
DISABLE:
- Install CMIT software from Windows.old
- Redirect ClipSVC\AltActivationClient → CmitClient.exe
- Register CmitClientSVC / Daily Runner recreate
- EPrivilege.exe -U:S CMGEInstaller.exe 00000200
- ALL certificate operations: RemoveCert + Import-Certificate (CMIT, gov, DigiCert) fully disabled
- Register SMx (Wst*Config -register)
PRESERVE:
- LGPO /g import
- secedit /configure, auditpol /restore
- Disable Defender/Netlogon/wlidsvc via sc
- Telemetry/privacy registry

### UpgradeSchdTask.exe (upgrade task)
DISABLE:
- Unregister-ScheduledTask UpgradeSchdTask (keep unregister? — it removes CMIT task, harmless; leave as-is)
- InstallUtil CmitClientSVC + DelayedAutostart
- EPrivilege.exe -U:S CMGEInstaller.exe 00000400
- Copy msvcr110*.dll to System32/SysWOW64 (CMIT dependency)
PRESERVE: none critical (all CMIT-specific); the unregister line is itself anti-CMIT, keep.

### ResetPreConfig.exe (reset pre)
DISABLE:
- Set-RegistryValue ClipSVC\AltActivationClient → CmitClient.exe
- EPrivilege.exe -U:S CMGEInstaller.exe 01000000
- CmitUpdateAgent.exe install/config
- CMITControlCenter shortcuts
- SMx register (Wst*Config.exe -register, win32+win64)
PRESERVE:
- LGPO.exe /g import (local policy — keep)
- (all cert imports disabled — 19 Import-Certificate/InstallCert calls disabled in clean build)

### ResetPostConfig.exe (reset post)
DISABLE:
- EPrivilege.exe -U:S CMGEInstaller.exe 02000000
- InstallUtil CmitClientSVC.exe + DelayedAutostart
- Register-ScheduledTask "CmitUpdateAgent Daily Runner"
PRESERVE: none critical (all CMIT-specific)

## 4. Certificate import (from InsPreConfig + Basic/FactoryAfterImageApply.cmd)

Import targets (all into LocalMachine):
- Beijing ROOT CA (+New) → Root        [DISABLE — privacy-first]
- Beijing GCA (+New) → CA              [DISABLE]
- BJCA (+New) → CA                     [DISABLE]
- CEGN_RCA → Root, CEGN_OCA → CA       [DISABLE]
- GDCA_Root_CA → Root, GDCA_Guangdong → CA  [DISABLE]
- SHECA → (was removed in UpgradeConfig, not reimported)  [DISABLE]
- UCA Root → Root                      [DISABLE]
- ROOTCA (CN=ROOTCA, O=OSCCA) → Root   [DISABLE — expired 2025/8/23]
- CMIT Root Authority → Root           [DISABLE — backdoor]
- CMIT SubP → CA                       [DISABLE — backdoor]
- CMIT signature → TrustedPublisher    [DISABLE — backdoor]
- DigiCert Assured ID / Global / High Assurance EV → Root  [DISABLE — Win10 ships these via root update; no deploy-time import needed]

Action: in all 6 exes, comment out every `Import-Certificate` / `InstallCert` / `RemoveCert` call.
Certificate imports are unnecessary: Windows 10 includes DigiCert roots by default
via Microsoft Root Certificate Program (KB931125 / Windows Update), and CMIT/government
CA certs are removed for privacy. All `RemoveCert` calls (remove-then-reimport pattern
in UpgradeConfig) are also disabled since the corresponding re-import is disabled.
