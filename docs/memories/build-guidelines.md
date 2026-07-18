# Build & Compilation Guidelines

## PS2EXE: Compiling PowerShell Scripts to EXE

All deployment EXEs in `dist/` are compiled from `.ps1` scripts in `build/` using [PS2EXE](https://github.com/MScholtes/PS2EXE) (`Invoke-ps2exe`, v0.5.0.34+).

### Required Flags

```
-noConsole         # GUI mode — no console window (deployment tools run silently)
-noOutput          # Suppress PowerShell output stream
-requireAdmin      # Embed UAC elevation manifest into the EXE
-x64               # Target 64-bit
```

### Prohibited Flags

```
-noError           # DO NOT USE — swallows script exceptions silently
```

**Why:** Without `-noError`, if the embedded PowerShell script throws an exception, Windows shows an error dialog (system tray popup in `-noConsole` mode). This lets users and developers know something went wrong. `-noError` masks all errors in silent mode, making deployment failures impossible to diagnose.

### Example

```powershell
Invoke-ps2exe -inputFile "build\ResetPreConfig.clean.ps1" `
              -outputFile "dist\ResetPreConfig.exe" `
              -noConsole -noOutput -requireAdmin -x64
```

### Verification

Use the built-in `-extract:` parameter to verify the embedded script:

```powershell
dist\ResetPreConfig.exe "-extract:C:\temp\verify.ps1"
Get-Content C:\temp\verify.ps1
```

## IExpress: Self-Extracting CAB Packages

Some CMIT update packages (`.exe` files) are Microsoft IExpress self-extracting CAB archives. Use `expand.exe` (built-in Windows) to extract:

```
expand.exe -F:* payload.cab C:\target\
```

## WIM Image Management

```
wimlib-imagex info install.wim          # List image indexes
wimlib-imagex mountrw install.wim 1 mount/  # Mount read-write
wimlib-imagex unmount mount/ --commit   # Commit changes
```

## MSI Extraction (for analysis, not production)

Use `msiexec /a` for admin install (extracts files without running Custom Actions), or extract the embedded CAB directly:

```powershell
# Locate MSCF (CAB) offset in MSI binary, then:
expand.exe -F:* extracted.cab C:\target\
```

## Tool Chain Versions (reference)

| Tool | Version | Notes |
|------|---------|-------|
| ps2exe (PowerShell module) | 1.0.18 | `Install-Module -Name ps2exe` |
| wimlib-imagex | 1.14.5 | WIM management |
| expand.exe | Built-in | Windows CAB extraction |
| certutil.exe | Built-in | Certificate management |
