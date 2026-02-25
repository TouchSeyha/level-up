# level-up

A single-command bulk updater for Windows 11 (PowerShell). Save all your tool
update commands once, then run them all with `level-up all` — or target
specific tools by name.

## Demo

https://github.com/user-attachments/assets/904b37c1-ad9b-40fd-a52a-ff326f1e7811

---

## Requirements

- Windows 11
- PowerShell 5.1 or PowerShell 7+ (`pwsh`)
- The tools you want to update already installed and available in `PATH`

---

## Installation

### 1. Place the script

The script lives at:

```
C:\Tools\level-up\level-up.ps1
```

If you cloned or downloaded this repo elsewhere, move or copy the folder to
`C:\Tools\level-up\`.

### 2. Allow script execution (if not already set)

Open PowerShell as Administrator and run once:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3. Add `level-up` to your PowerShell profile

Run this command in any PowerShell terminal:

```powershell
& "C:\Tools\level-up\level-up.ps1" alias --install
```

This appends a `level-up` function to your `$PROFILE` file so you can call
`level-up` from any terminal without typing the full path.

Reload your profile (or open a new terminal):

```powershell
. $PROFILE
```

You are now ready.

---

## Quick start

```powershell
# Add your first tool
level-up add

# Verify the list
level-up list

# Run a single tool update
level-up run codex

# Run all saved updates
level-up all
```

---

## Command reference

| Command | Description |
|---|---|
| `level-up list` | Print all configured entries |
| `level-up add` | Interactively add a new entry |
| `level-up remove <name>` | Delete an entry by name |
| `level-up run <name> [name...]` | Run one or more entries by name |
| `level-up all` | Run every configured entry |
| `level-up edit` | Open the config file in `$EDITOR` / Notepad |
| `level-up doctor` | Check that each tool's executable exists in PATH |
| `level-up alias --install` | Write `level-up` function to `$PROFILE` |
| `level-up alias --add <name>` | Write `level-up-<name>` shortcut to `$PROFILE` |
| `level-up log` | Print the most recent run log |
| `level-up help` | Show help text |

---

## Adding entries

```powershell
level-up add
```

You will be prompted for:

```
  Name (e.g. codex, claude)       : codex
  Command (e.g. npm i -g @openai/codex@latest) : npm i -g @openai/codex@latest
```

Names must be unique. If a name already exists, remove it first.

### Example entries

| Name | Command |
|---|---|
| `claude` | `claude update` |
| `opencode` | `opencode upgrade` |
| `codex` | `npm i -g @openai/codex@latest` |
| `bun` | `bun upgrade` |
| `deno` | `deno upgrade` |

---

## Running updates

### Run everything

```powershell
level-up all
```

Output:

```
==> claude
    claude update
    [OK] exit 0  (3s)

==> codex
    npm i -g @openai/codex@latest
    [OK] exit 0  (12s)

--- Summary ---
  Passed : 2
  Failed : 0
  Log    : C:\Users\you\AppData\Local\level-up\logs\2026-02-25_143022.log
```

### Run specific tools

```powershell
level-up run codex
level-up run codex claude opencode
```

### Failure behavior

All commands always run regardless of individual failures (continue-on-error).
At the end, a summary lists which passed and which failed. The process exits
with code `1` if any command failed, so CI scripts can detect failures.

---

## Per-tool shortcuts (optional)

Add a dedicated shortcut function for any saved entry:

```powershell
level-up alias --add codex
```

This appends to `$PROFILE`:

```powershell
function level-up-codex { & "C:\Tools\level-up\level-up.ps1" run codex }
```

After reloading your profile you can run:

```powershell
level-up-codex
```

---

## Doctor — health check

Check that every saved tool's executable is available in `PATH`:

```powershell
level-up doctor
```

Output:

```
  Checking tools...

  [OK]      claude    C:\Users\you\AppData\Roaming\npm\claude.cmd
  [OK]      codex     C:\Users\you\AppData\Roaming\npm\npm.cmd
  [MISSING] mytool    'mytool' not found in PATH
```

Exits with code `1` if anything is missing.

---

## Config file

Config is stored as JSON at:

```
%LOCALAPPDATA%\level-up\commands.json
```

Full path example:

```
C:\Users\you\AppData\Local\level-up\commands.json
```

Format:

```json
{
  "commands": [
    { "name": "claude",    "command": "claude update" },
    { "name": "opencode",  "command": "opencode upgrade" },
    { "name": "codex",     "command": "npm i -g @openai/codex@latest" }
  ]
}
```

You can edit this directly with `level-up edit` or any text editor.

---

## Run logs

Every `level-up all` or `level-up run` writes a timestamped log to:

```
%LOCALAPPDATA%\level-up\logs\YYYY-MM-DD_HHmmss.log
```

View the most recent log:

```powershell
level-up log
```

Log format:

```
[2026-02-25 14:30:22] === level-up all ===
[2026-02-25 14:30:22] --> codex: npm i -g @openai/codex@latest
[2026-02-25 14:30:35] <-- codex: EXIT 0 (13s)
[2026-02-25 14:30:35] --> claude: claude update
[2026-02-25 14:30:36] <-- claude: EXIT 0 (1s)
[2026-02-25 14:30:36] === SUMMARY: 2 passed, 0 failed ===
```

---

## Execution model

Commands are run via `Invoke-Expression` in the **current shell session**.
This means they inherit your `PATH`, environment variables, and any tools
installed via `nvm`, `volta`, `scoop`, etc.

If a command contains embedded quotes, escape them at `add` time:

```
Command: npm i -g "some package"
```

---

## Uninstall

1. Delete the script folder: `C:\Tools\level-up\`
2. Delete the config + logs: `%LOCALAPPDATA%\level-up\`
3. Remove the `# >>> level-up ... # <<< level-up` block from your `$PROFILE`

---

## Testing checklist

```powershell
# 1. Add some entries
level-up add   # name: claude,   command: claude update
level-up add   # name: opencode, command: opencode upgrade
level-up add   # name: codex,    command: npm i -g @openai/codex@latest

# 2. Verify list
level-up list

# 3. Run a single tool
level-up run codex

# 4. Run multiple tools
level-up run codex claude

# 5. Run everything
level-up all

# 6. Remove an entry
level-up remove codex
level-up list   # codex should be gone

# 7. Health check
level-up doctor

# 8. Check a failed command returns exit code 1
level-up run nonexistent-tool
echo "Exit: $LASTEXITCODE"   # should be 1

# 9. Profile function works in a new terminal
level-up alias --install
# open new terminal, then:
level-up list
```
