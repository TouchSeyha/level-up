# Security Policy

## Supported Versions

This project is currently maintained as a single script. Security fixes are provided for the latest code on the `main` branch.

| Version | Supported |
| --- | --- |
| Latest `main` | ✅ |
| Older snapshots/forks | ❌ |

## Reporting a Vulnerability

Please report security issues privately.

- Preferred: GitHub private vulnerability report (Security Advisory)
  - https://github.com/TouchSeyha/level-up/security/advisories/new
- If that link is unavailable, open a normal issue only for non-sensitive bugs. Do **not** post exploit details, secrets, tokens, or private environment info publicly.

## What to Include

Include as much of the following as possible:

- A clear description of the vulnerability and impact
- Reproduction steps (minimal and reliable)
- Affected environment (Windows version, PowerShell version)
- The command/config shape that triggers the issue (redact secrets)
- Any suggested mitigation or patch ideas

## Response Expectations

- Initial triage response target: within 7 days
- If confirmed, a fix or mitigation plan will be shared as soon as practical
- Coordinated disclosure is preferred: please allow time for a patch before public disclosure

## Security Considerations for `level-up`

Because this tool executes configured commands, treat command entries as trusted input:

- Only add commands you understand and trust
- Review `%LOCALAPPDATA%\level-up\commands.json` before running `level-up all`
- Avoid storing secrets directly in commands
- Use least-privilege shells when possible
- Review `%LOCALAPPDATA%\level-up\logs\` before sharing logs publicly (they may contain command output)

## Scope

This policy covers the contents of this repository. Vulnerabilities in third-party tools invoked by saved commands (for example `npm`, `bun`, `deno`, or other package managers) should also be reported to those upstream projects.
