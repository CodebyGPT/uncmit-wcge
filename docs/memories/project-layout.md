# Project Layout & Environment

## Repository Structure

```
uncmit-wcge/
│
├── build/                    # PowerShell source scripts (.ps1) for deployment EXEs
├── dist/                     # Compiled EXEs (gitignored; rebuilt locally)
├── src/                      # Supporting scripts
│   └── uncmit-cleanup.cmd    # Post-reverse cleanup script
├── reverse/                  # Reverse engineering analysis of CMIT binaries
│   ├── ilspy/                # ILSpy decompilation output (.NET assemblies)
│   ├── *.extracted.ps1       # PowerShell scripts extracted from compiled EXEs
│   └── *CKB20*.ps1           # Scripts extracted from official CMIT CKB packages
├── docs/                     # Analysis reports and design docs
│   └── memories/             # Project knowledge base (this directory)
├── skills/                   # Reasonix/AI skill definitions
│   └── 制作外置应答文件/       # Windows Unattend.xml authoring skill
│
├── .gitattributes            # *.cmd -text (CRLF enforcement)
├── .gitignore
└── README.md
```

### What is NOT tracked in git (local-only)

| Path | Reason |
|------|--------|
| `*.exe` in `dist/` | Build artifacts — compile from `build/*.ps1` (see `build-guidelines.md`) |
| `*.cab`, extracted MSI/CAB contents | Analysis artifacts from CKB/MSI reverse engineering — ephemeral |

## OS Image Context

The project targets **Windows 10 EnterpriseG (神州网信政府版)**:

- **Edition:** Windows 10 EnterpriseG (zh-CN) — CMIT/SMG Government Edition
- **Architecture/Build:** x86_64, Build 19044.1415
- **Base Version:** V2022-L.1345.000
- **WIM size:** ~3.96 GB compressed / ~13 GB decompressed (~94K files, ~27K dirs)

## Tool Chain

| Tool | Purpose |
|------|---------|
| [PS2EXE](https://github.com/MScholtes/PS2EXE) (v1.0.18) | Compile PowerShell → standalone EXE |
| `expand.exe` (built-in) | Extract Microsoft CAB archives |
| `certutil.exe` (built-in) | Certificate management & binary dump |
| `msiexec.exe` (built-in) | MSI database query & admin install |
| wimlib-imagex (1.14.5) | WIM image mount/extract/commit |
| Python 3.14 | Binary analysis (PE, CAB, MSI parsing) |
| ILSpy | .NET assembly decompilation |
| PowerShell | MSI COM automation and file analysis |

## Key File Types Encountered

| Type | Identify By | Extraction |
|------|-------------|------------|
| MSI installer | `D0 CF 11 E0` (OLE) or `.msi` extension | `msiexec /a` or extract embedded MSCF CAB |
| IExpress self-extract | PE header + `MSCF` signature inside | `expand.exe -F:*` |
| InstallUtil assembly | .NET PE, references `System.Configuration.Install` | ILSpy decompilation |
| PS2EXE | .NET PE, references `ik.PowerShell` | `exe -extract:file.ps1` |

## GDCA Certificates (imported by CKB2024103103)

| Subject | Store | SHA1 Fingerprint |
|---------|-------|------------------|
| `GDCA ROOT CA1` | Root | `0a8f0029ea3cd051a30133bd7aa6eccff8ffedc6` |
| `GDCA Public CA1` | CA (Intermediate) | `f68709c71b4a14df2bd855129a2605c34eb9d955` |
| `GDCA Public CA2` | CA (Intermediate) | `d1ab2aba7e4b4dc6dfc48ba665e1e6ad740b185b` |

Guangdong Digital Certificate Authority (GDCA) — a Chinese government-approved Certificate Authority. These certs enable trust for GDCA-signed code and SSL certificates.
