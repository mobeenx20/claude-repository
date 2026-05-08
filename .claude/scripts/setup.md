# Claude Setup Script

This document describes `.claude/scripts/setup.sh`, a bootstrap script for configuring Claude Code in this repository.

## Purpose

The script standardizes local Claude Code setup for contributors by installing required plugins, wiring RTK, and applying project defaults.

## Prerequisites

- Claude Code CLI is installed and available on `PATH` (`claude` command).
- Python 3 is available (`python3` command).
- Git is installed (`git` command) — used to resolve the project root.
- `rtk` can be installed:
    - macOS: Homebrew must be installed.
    - Linux: `curl` is required.
- Network access is available for plugin and dependency installation.

## Run

From anywhere inside the repository:

```bash
bash .claude/scripts/setup.sh
```

The script resolves the project root via `git rev-parse --show-toplevel`, so it works regardless of the current working directory.

## What the script does

### 1) Preflight checks

- Verifies `claude` CLI is available.

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

### 5) Global status line integration

- If available in plugin cache, sets global status line command in `~/.claude/settings.json` to caveman statusline hook.

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

## Idempotency

The script is designed to be re-runnable:

- Existing plugins are detected and skipped by CLI.
- Existing hook entries are detected before insertion.
- Project defaults are re-applied safely.

## Notes

- After setup completes, restart Claude Code so hooks and model settings are fully applied.
- If a step fails due to environment constraints, resolve the prerequisite and rerun the script.
