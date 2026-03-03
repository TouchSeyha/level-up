# Changelog

All notable changes to this project will be documented in this file.

## [0.0.3] - 2026-03-03

### Added
- Cross-shell launchers:
  - `level-up.cmd` for CMD / Windows shell command resolution
  - `level-up` Bash launcher for Git Bash
- `level-up alias --install-bash` to register `level-up` in `~/.bashrc`
- Wrapper fallback behavior:
  - Prefer `pwsh` when available
  - Fallback to `powershell.exe`

### Changed
- Documentation updated for PowerShell, Git Bash, and CMD usage
- Execution model docs now clarify wrapper behavior and path conversion handling

## [0.0.2] - 2026-02-26

### Added
- **Enable/Disable Commands** — Users can now enable or disable individual commands without removing them entirely.
  - `level-up disable <name>` — Disable a command
  - `level-up enable <name>` — Re-enable a disabled command
  - New entries are enabled by default

### Changed
- **`level-up list`** — Now displays a STATUS column showing whether each command is enabled or disabled
  - Enabled commands appear in white with green STATUS
  - Disabled commands appear dimmed (gray) with red STATUS
- **`level-up all`** — Now only runs enabled commands. If all commands are disabled, displays a helpful message instead of running nothing.
- **`level-up run <name>`** — When targeting a disabled command explicitly, shows a warning message and skips it
- **`level-up doctor`** — Shows `[DISABLED]` status for disabled commands instead of checking PATH

### Fixed
- Backward compatibility: Config files without the `enabled` field are automatically migrated

## [0.0.1] - 2025-01-01

### Added
- Initial release
- Core commands: add, remove, list, run, all
- Profile alias integration
- Doctor check and log viewing
