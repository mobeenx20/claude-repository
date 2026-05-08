#!/usr/bin/env bash
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

step "Preflight"
command -v claude >/dev/null 2>&1 || {
  echo "Error: 'claude' CLI not on PATH. Install Claude Code first: https://claude.com/claude-code" >&2
  exit 1
}
command -v git >/dev/null 2>&1 || {
  echo "Error: 'git' not found. Install git and re-run." >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "Error: 'python3' not found. Install Python 3 and re-run." >&2
  exit 1
}

step "Plugin marketplaces"
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add ChromeDevTools/chrome-devtools-mcp

step "Plugins (project scope — claude-plugins-official)"
claude plugin install skill-creator@claude-plugins-official --scope project
claude plugin install claude-md-management@claude-plugins-official --scope project
claude plugin install session-report@claude-plugins-official --scope project
claude plugin install playwright@claude-plugins-official --scope project
claude plugin install context7@claude-plugins-official --scope project
claude plugin install frontend-design@claude-plugins-official --scope project
claude plugin install feature-dev@claude-plugins-official --scope project
claude plugin install superpowers@claude-plugins-official --scope project

step "Plugins (project scope — third-party)"
claude plugin install caveman@caveman --scope project
claude plugin install chrome-devtools-mcp@chrome-devtools-plugins --scope project

step "RTK binary"
if command -v rtk >/dev/null 2>&1; then
  echo "rtk already installed: $(command -v rtk)"
else
  os="$(uname -s)"
  case "$os" in
    Darwin)
      command -v brew >/dev/null 2>&1 || {
        echo "Error: Homebrew not found. Install it from https://brew.sh, then re-run this script." >&2
        exit 1
      }
      brew install rtk
      ;;
    Linux)
      curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
      ;;
    *)
      echo "Error: unsupported OS '$os'. RTK install supports Darwin (macOS) and Linux." >&2
      exit 1
      ;;
  esac
  command -v rtk >/dev/null 2>&1 || {
    echo "Error: rtk install reported success but binary not on PATH. Check shell rc or restart shell." >&2
    exit 1
  }
fi

step "Wire RTK into Claude Code (global)"
rtk init -g --auto-patch

step "RTK enforcement hook (project-scoped)"
mkdir -p .claude/hooks
cat > .claude/hooks/enforce-rtk.sh <<'HOOK'
#!/usr/bin/env bash
INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('command',''))" 2>/dev/null)

[[ -z "$CMD" || "$CMD" == rtk\ * ]] && exit 0
[[ "$CMD" == *'&&'* || "$CMD" == *'||'* || "$CMD" == *';'* || "$CMD" == *'|'* ]] && exit 0

case "$CMD" in
    git\ *|git) echo "Use: rtk $CMD"; exit 1 ;;
    ls\ *|ls)   echo "Use: rtk $CMD"; exit 1 ;;
    grep\ *)    echo "Use: rtk $CMD"; exit 1 ;;
esac

exit 0
HOOK
chmod +x .claude/hooks/enforce-rtk.sh
python3 - <<'PY'
import json, pathlib
p = pathlib.Path(".claude/settings.local.json")
data = json.loads(p.read_text()) if p.exists() else {}
hooks = data.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])
already = any(
    h.get("matcher") == "Bash"
    and any(hh.get("command", "").endswith("enforce-rtk.sh") for hh in h.get("hooks", []))
    for h in pre
)
if not already:
    pre.append({
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": ".claude/hooks/enforce-rtk.sh"}]
    })
    p.write_text(json.dumps(data, indent=2) + "\n")
    print("✓ RTK enforcement hook added to settings.local.json")
else:
    print("✓ RTK enforcement hook already present in settings.local.json")
PY

step "Caveman statusline badge (global)"
caveman_statusline=$(/bin/ls -dt "$HOME"/.claude/plugins/cache/caveman/caveman/*/hooks/caveman-statusline.sh 2>/dev/null | head -1)
if [ -f "$caveman_statusline" ]; then
  CAVEMAN_STATUSLINE_PATH="$caveman_statusline" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.path.expanduser("~/.claude/settings.json"))
data = json.loads(p.read_text()) if p.exists() else {}
data["statusLine"] = {
    "type": "command",
    "command": f'bash "{os.environ["CAVEMAN_STATUSLINE_PATH"]}"'
}
p.write_text(json.dumps(data, indent=2) + "\n")
PY
  echo "✓ statusLine -> $caveman_statusline"
else
  echo "Skipped: caveman-statusline.sh not found in plugin cache."
fi

step "Enable plugins (project-scoped)"
python3 - <<'PY'
import json, pathlib
p = pathlib.Path(".claude/settings.json")
data = json.loads(p.read_text()) if p.exists() else {}
ep = data.setdefault("enabledPlugins", {})
for plugin in [
    "skill-creator@claude-plugins-official",
    "claude-md-management@claude-plugins-official",
    "session-report@claude-plugins-official",
    "playwright@claude-plugins-official",
    "context7@claude-plugins-official",
    "frontend-design@claude-plugins-official",
    "feature-dev@claude-plugins-official",
    "superpowers@claude-plugins-official",
    "caveman@caveman",
    "chrome-devtools-mcp@chrome-devtools-plugins",
]:
    ep[plugin] = True
data.setdefault("env", {})["CAVEMAN_DEFAULT_MODE"] = "ultra"
p.write_text(json.dumps(data, indent=2) + "\n")
print("✓ All plugins enabled in settings.json")
print("✓ Caveman default set to ultra")
PY

step "Caveman session config (project-scoped)"
if [ ! -t 0 ]; then
  echo "Non-interactive shell — skipping caveman prompt. Caveman stays enabled at default intensity ('ultra')."
else
  read -r -p "Enable caveman mode for all sessions of this project? [y/N] " ans
  case "${ans:-n}" in
    [yY]|[yY][eE][sS])
      echo
      echo "Intensity levels:"
      echo "  1) lite  — drop articles + filler, keep most structure"
      echo "  2) full  — classic caveman: fragments OK, short synonyms"
      echo "  3) ultra — maximum compression"
      read -r -p "Pick [1-3, default 3=ultra]: " choice
      case "${choice:-3}" in
        1) level=lite ;;
        2) level=full ;;
        *) level=ultra ;;
      esac
      CAVEMAN_LEVEL="$level" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(".claude/settings.json")
data = json.loads(p.read_text())
data.setdefault("env", {})["CAVEMAN_DEFAULT_MODE"] = os.environ["CAVEMAN_LEVEL"]
p.write_text(json.dumps(data, indent=2) + "\n")
PY
      echo "✓ Caveman locked to '$level' in .claude/settings.json (env.CAVEMAN_DEFAULT_MODE)."
      ;;
    *)
      claude plugin uninstall caveman@caveman --scope project >/dev/null 2>&1 || true
      echo "✓ Caveman not enabled for this project. For full removal (flag file, statusline, marketplace), run: ./.claude/disable-caveman.sh"
      ;;
  esac
fi

printf '\n\033[1;32m✓ Setup complete.\033[0m Restart Claude Code so hooks activate.\n'
