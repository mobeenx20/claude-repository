# Claude Setup Script

This document describes `.claude/scripts/setup.sh`, a bootstrap script for configuring Claude Code in this repository.

## Purpose

The script standardizes local Claude Code setup for contributors by installing required plugins, wiring RTK, and applying project defaults.

## Prerequisites

- Claude Code CLI is installed and available on `PATH` (`claude` command).
- Python 3 is available (`python3` command).
- `jq` is installed (`jq` command) — used by the statusline script to parse Claude Code JSON.
- Git is installed (`git` command) — used to resolve the project root.
- `rtk` can be installed:
    - macOS: Homebrew must be installed.
    - Linux: `curl` is required.
- Network access is available for plugin and dependency installation.

## Run

From the repository root:

```bash
bash .claude/scripts/setup.sh
```

The script resolves the project root internally via `git rev-parse --show-toplevel`, so it remains safe if invoked from a wrapper or alias.

## What the script does

### 1) Preflight checks

- Verifies `claude`, `git`, `python3`, and `jq` are available on `PATH`.

### 2) Plugin marketplace setup

- Adds marketplace `JuliusBrussee/caveman`.
- Adds marketplace `ChromeDevTools/chrome-devtools-mcp`.

### 3) Plugin installation (project scope)

Installs these plugins with `--scope project`:

- `skill-creator@claude-plugins-official`
- `claude-md-management@claude-plugins-official`
- `session-report@claude-plugins-official`
- `playwright@claude-plugins-official`
- `context7@claude-plugins-official`
- `frontend-design@claude-plugins-official`
- `feature-dev@claude-plugins-official`
- `superpowers@claude-plugins-official`
- `caveman@caveman`
- `chrome-devtools-mcp@chrome-devtools-plugins`

### 4) RTK installation and integration

- Ensures `rtk` is installed (or installs it for supported OS).
- Runs `rtk init -g --auto-patch` to register global RTK hook.
- Creates project hook at `.claude/hooks/enforce-rtk.sh`.
- Ensures hook registration exists in `.claude/settings.local.json`.

### 5) Project-aware status line

- Generates `~/.claude/statusline-command.sh` — a combined statusline showing:
    - Caveman badge — reads `env.CAVEMAN_DEFAULT_MODE` from the project's `.claude/settings.json` using the CWD provided in stdin JSON. Falls back to the global flag file (`~/.claude/.caveman-active`) for projects without the env var. This ensures each project displays its own configured caveman level, even when multiple sessions are open simultaneously.
    - Git branch (current branch or short SHA)
    - Via tool (Node.js, Rust, Go, or Python — detected from project marker files)
    - Claude context info (model name, context usage %, effort level)
- Points `~/.claude/settings.json` statusLine at the generated script.
- Requires `jq` at runtime for parsing Claude Code's JSON input.
- Runtime mode changes via `/caveman lite` are not reflected in the badge (the per-turn text reinforcement still shows the correct mode).

### 6) Project defaults in `.claude/settings.json`

Sets or updates:

- `enabledPlugins`: ensures all required plugin entries are enabled
- `env.CAVEMAN_DEFAULT_MODE`: `ultra`

### 7) Caveman session configuration

- Non-interactive shells skip prompt and keep default (`ultra`).
- Interactive shells prompt whether to enable caveman for project and optionally choose intensity.

## Files this script may modify

- `.claude/hooks/enforce-rtk.sh`
- `.claude/settings.local.json`
- `.claude/settings.json`
- `~/.claude/settings.json` (global user settings)
- `~/.claude/statusline-command.sh` (generated statusline script)

## Idempotency

The script is designed to be re-runnable:

- Existing plugins are detected and skipped by CLI.
- Existing hook entries are detected before insertion.
- Project defaults are re-applied safely.

## Notes

- After setup completes, restart Claude Code so hooks and model settings are fully applied.
- If a step fails due to environment constraints, resolve the prerequisite and rerun the script.
