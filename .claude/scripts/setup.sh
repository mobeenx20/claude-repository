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
command -v jq >/dev/null 2>&1 || {
  echo "Error: 'jq' not found. Install jq (brew install jq / apt install jq) and re-run." >&2
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

step "Statusline (global: caveman + git branch + via tool + Claude context)"
statusline_script="$HOME/.claude/statusline-command.sh"

cat > "$statusline_script" <<'STATUSLINE'
#!/usr/bin/env bash
INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

# Caveman badge — reads project config so each project shows its own level
CAVEMAN=""
CAVEMAN_MODE=""
if [ -n "$CWD" ] && [ -f "$CWD/.claude/settings.json" ]; then
  CAVEMAN_MODE=$(jq -r '.env.CAVEMAN_DEFAULT_MODE // empty' "$CWD/.claude/settings.json" 2>/dev/null)
fi
if [ -z "$CAVEMAN_MODE" ]; then
  FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
  if [ -f "$FLAG" ] && [ ! -L "$FLAG" ]; then
    CAVEMAN_MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  fi
fi
case "$CAVEMAN_MODE" in
  lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress)
    if [ "$CAVEMAN_MODE" = "full" ]; then
      CAVEMAN=$(printf '\033[38;5;172m[CAVEMAN]\033[0m')
    else
      SUFFIX=$(printf '%s' "$CAVEMAN_MODE" | tr '[:lower:]' '[:upper:]')
      CAVEMAN=$(printf '\033[38;5;172m[CAVEMAN:%s]\033[0m' "$SUFFIX")
    fi
    ;;
esac
if [ -n "$CAVEMAN" ] && [ "${CAVEMAN_STATUSLINE_SAVINGS:-1}" != "0" ]; then
  SAVINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-statusline-suffix"
  if [ -f "$SAVINGS_FILE" ] && [ ! -L "$SAVINGS_FILE" ]; then
    SAVINGS=$(head -c 64 "$SAVINGS_FILE" 2>/dev/null | tr -d '\000-\037')
    [ -n "$SAVINGS" ] && CAVEMAN="$CAVEMAN $(printf '\033[38;5;172m%s\033[0m' "$SAVINGS")"
  fi
fi

# Git branch
BRANCH=""
command -v git &>/dev/null && BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
GIT_OUT=""
[ -n "$BRANCH" ] && GIT_OUT=$(printf '\033[38;5;78m\xef\x90\x98 %s\033[0m' "$BRANCH")

# Via tool (starship-style language detection)
VIA=""
if [ -n "$CWD" ]; then
  if [ -f "$CWD/package.json" ]; then
    NODE_V=$(node -v 2>/dev/null)
    [ -n "$NODE_V" ] && VIA=$(printf 'via \033[38;5;78m\xf3\xb0\x8e\x99 Node.js %s\033[0m' "$NODE_V")
  elif [ -f "$CWD/Cargo.toml" ]; then
    RUST_V=$(rustc --version 2>/dev/null | awk '{print $2}')
    [ -n "$RUST_V" ] && VIA=$(printf 'via \033[38;5;208m\xef\x90\xa8 %s\033[0m' "$RUST_V")
  elif [ -f "$CWD/go.mod" ]; then
    GO_V=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
    [ -n "$GO_V" ] && VIA=$(printf 'via \033[38;5;81m\xef\x90\xa8 %s\033[0m' "$GO_V")
  elif [ -f "$CWD/requirements.txt" ] || [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/setup.py" ]; then
    PY_V=$(python3 --version 2>/dev/null | awk '{print $2}')
    [ -n "$PY_V" ] && VIA=$(printf 'via \033[38;5;220m\xef\x90\xa8 python %s\033[0m' "$PY_V")
  fi
fi

# Claude Code info
MODEL=$(printf '%s' "$INPUT" | jq -r '.model.display_name // empty')
USED=$(printf '%s' "$INPUT" | jq -r '.context_window.used_percentage // empty')
EFFORT=$(printf '%s' "$INPUT" | jq -r '.effort.level // empty')

CLAUDE_PARTS=()
[ -n "$MODEL" ] && CLAUDE_PARTS+=("$(printf '\033[38;5;75m%s\033[0m' "$MODEL")")
if [ -n "$USED" ]; then
  USED_INT=$(printf '%.0f' "$USED")
  if [ "$USED_INT" -ge 80 ]; then
    COLOR='\033[38;5;196m'
  elif [ "$USED_INT" -ge 50 ]; then
    COLOR='\033[38;5;220m'
  else
    COLOR='\033[38;5;71m'
  fi
  CLAUDE_PARTS+=("$(printf "${COLOR}ctx:%s%%\033[0m" "$USED_INT")")
fi
[ -n "$EFFORT" ] && CLAUDE_PARTS+=("$(printf '\033[38;5;141m%s\033[0m' "$EFFORT")")

CLAUDE_OUT=""
for part in "${CLAUDE_PARTS[@]}"; do
  [ -n "$CLAUDE_OUT" ] && CLAUDE_OUT="$CLAUDE_OUT $(printf '\033[38;5;240m|\033[0m') "
  CLAUDE_OUT="$CLAUDE_OUT$part"
done

# Combine sections
SECTIONS=()
[ -n "$CAVEMAN" ] && SECTIONS+=("$CAVEMAN")
[ -n "$GIT_OUT" ] && SECTIONS+=("$GIT_OUT")
[ -n "$VIA" ] && SECTIONS+=("$VIA")
[ -n "$CLAUDE_OUT" ] && SECTIONS+=("$CLAUDE_OUT")

OUTPUT=""
for section in "${SECTIONS[@]}"; do
  [ -n "$OUTPUT" ] && OUTPUT="$OUTPUT  "
  OUTPUT="$OUTPUT$section"
done
[ -n "$OUTPUT" ] && printf '%s' "$OUTPUT"
STATUSLINE
chmod +x "$statusline_script"
echo "✓ Wrote $statusline_script"

# Point global settings.json at combined script (runs AFTER plugin installs to override caveman's statusLine)
python3 - "$statusline_script" <<'PY'
import json, os, sys, pathlib
p = pathlib.Path(os.path.expanduser("~/.claude/settings.json"))
data = json.loads(p.read_text()) if p.exists() else {}
data["statusLine"] = {
    "type": "command",
    "command": f'bash "{sys.argv[1]}"'
}
p.write_text(json.dumps(data, indent=2) + "\n")
print("✓ statusLine in ~/.claude/settings.json -> " + sys.argv[1])
print("  (overrides caveman plugin's statusLine — combined script includes caveman badge)")
PY

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
