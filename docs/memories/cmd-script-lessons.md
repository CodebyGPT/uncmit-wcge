# Windows .cmd Batch Script Lessons Learned

Derived from developing `src/uncmit-cleanup.cmd`.

## Key Pitfalls

### 1. `else` Must Follow `)` on the Same Physical Line

cmd.exe does NOT allow `else` on its own line — even indented.

```cmd
:: ❌ ERROR: 'else' is not recognized
if exist "%~1" (
    rmdir /s /q "%~1"
) else call :log_skip "not found"

:: ✅ Correct
if exist "%~1" (
    rmdir /s /q "%~1"
) else call :log_skip "not found"
```

**Rule:** The `)` and `else` must share one physical line.

### 2. CRLF Line Endings Are Mandatory

cmd.exe requires `.cmd`/`.bat` files to use `0D 0A` (CRLF) line endings. LF-only files cause bizarre parse errors — leading characters get swallowed (`title` → `itle`, `setlocal` → parsed as command name).

**Impact on GitHub:**
- `text eol=crlf` in `.gitattributes` **only guarantees CRLF on git checkout**.
- GitHub raw download (`raw.githubusercontent.com`) returns the blob as-is, bypassing checkout conversion.
- Therefore the blob itself must contain CRLF. Use `-text` to prevent git from normalizing.

**Correct approach:**
```gitattributes
*.cmd -text
```

`-text` tells git to do no line-ending conversion — the blob stores raw bytes as written. Verify with `git ls-files --eol` confirming `i/crlf`.

### 3. `::` Comment Pitfalls in Blocks

`::` is a hack that creates an invalid label target — it is NOT a real comment. Using `::` inside `if`/`for` blocks can cause parse errors.

| Context | Safe | Unsafe |
|---------|------|--------|
| Outside blocks (`if`/`for`) | `::` | — |
| Inside blocks | `rem` | `::` |

**Rule:** Use `::` only at top level for section headers; use `rem` inside `if (...)` or `for (...)` blocks.

### 4. `2>nul` Silently Swallows Errors

```cmd
rmdir /s /q "path" 2>nul
if exist "path" (echo failure) else echo success
```

`2>nul` hides whether failure was "not found" or "access denied". Acceptable for end-users who only need the result, but during debugging temporarily remove `2>nul`.

### 5. `%*` in Subroutines

`call :sub "arg with spaces"` expands `%*` as `"arg with spaces"` (quotes included). `%~1` strips them. `echo %*` in a log function works fine normally, but special characters like `&`, `|`, and unmatched parentheses may be interpreted.

**Mitigation:** Wrap log parameters in quotes; avoid unmatched parentheses in log text.

### 6. Every Subroutine Must End With `exit /b`

`goto :main` at the top skips over subroutine definitions below. But when a subroutine is called from within another, **fall-through** to the next subroutine will corrupt control flow. Every `:label` block must end with `exit /b 0`.

### 7. Certificate Deletion Requires `echo Y|` Pipe

```cmd
echo Y 2>nul | certutil -delstore "Root" "CertName" >nul 2>nul
```

`certutil -delstore` prompts for confirmation. Piping `echo Y` auto-answers. The cert name supports fuzzy matching.

### 8. `-text` vs `text eol=crlf` for `.gitattributes`

| Scenario | `.gitattributes` | Raw download line endings |
|----------|-----------------|--------------------------|
| User clones via git | `text eol=crlf` | LF (ok) |
| User downloads from GitHub raw | `text eol=crlf` | **LF** (broken for cmd.exe) |
| User downloads from GitHub raw | `-text` | **CRLF** (correct) |

`.cmd` files MUST use `-text` because many sysadmins download via `curl.exe -LO` without git.

## Design Principle: Only Clean What Was Created

The cleanup script deletes files/registry entries/certificates that the deployment EXEs **actually create**. If a create operation was commented out in the original EXE source code (dead code) or skipped by `UNCMIT-DISABLED` markers, the cleanup script should NOT contain corresponding cleanup — it's redundant defensive code that only confuses users with a wall of `[SKIP]` messages.

Exception: If commented-out create operations correspond to files that may exist on disk from historical upgrades (old system state), they may be retained with explicit justification.
