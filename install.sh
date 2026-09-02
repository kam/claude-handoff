#!/usr/bin/env bash
# Install the handoff skill and hooks into ~/.claude.
#   ./install.sh            symlink (edits in this checkout apply immediately)
#   ./install.sh --copy     copy files instead of symlinking
#   ./install.sh --uninstall
# Merges the two hook entries into ~/.claude/settings.json (backup written first).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLAUDE="${CLAUDE_HOME:-$HOME/.claude}"
MODE="${1:-link}"

command -v python3 >/dev/null || { echo "python3 is required (hooks are Python)"; exit 1; }

if [ "$MODE" = "--uninstall" ]; then
  rm -rf "$CLAUDE/skills/handoff"
  rm -f "$CLAUDE/hooks/handoff-load.py" "$CLAUDE/hooks/handoff-precompact.py" "$CLAUDE/hooks/handoff_common.py"
  python3 - "$CLAUDE/settings.json" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
if not p.exists(): sys.exit(0)
d = json.loads(p.read_text()); h = d.get("hooks", {})
for ev in ("SessionStart", "PreCompact"):
    h[ev] = [e for e in h.get(ev, []) if not any("handoff-" in x.get("command", "") for x in e.get("hooks", []))]
    if not h[ev]: h.pop(ev)
p.write_text(json.dumps(d, indent=2) + "\n")
PY
  echo "Removed handoff skill, hooks and settings entries."
  exit 0
fi

mkdir -p "$CLAUDE/skills" "$CLAUDE/hooks"
place() {  # place <src> <dst>
  rm -rf "$2"
  if [ "$MODE" = "--copy" ]; then cp -R "$1" "$2"; else ln -s "$1" "$2"; fi
}
place "$HERE/skills/handoff" "$CLAUDE/skills/handoff"
for f in handoff-load.py handoff-precompact.py handoff_common.py; do
  place "$HERE/hooks/$f" "$CLAUDE/hooks/$f"
done

SETTINGS="$CLAUDE/settings.json"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak-handoff-$(date +%Y%m%d%H%M%S)"
python3 - "$SETTINGS" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text()) if p.exists() else {}
h = d.setdefault("hooks", {})
def has(ev, needle):
    return any(needle in x.get("command", "") for e in h.get(ev, []) for x in e.get("hooks", []))
if not has("SessionStart", "handoff-load.py"):
    h.setdefault("SessionStart", []).append({
        "matcher": "startup|resume|clear|compact",
        "hooks": [{"type": "command",
                   "command": "python3 \"$HOME/.claude/hooks/handoff-load.py\"",
                   "timeout": 10, "statusMessage": "Loading handoff"}]})
if not has("PreCompact", "handoff-precompact.py"):
    h.setdefault("PreCompact", []).append({
        "hooks": [{"type": "command",
                   "command": "python3 \"$HOME/.claude/hooks/handoff-precompact.py\"",
                   "timeout": 20, "statusMessage": "Writing handoff auto-snapshot"}]})
p.write_text(json.dumps(d, indent=2) + "\n")
PY
echo "Installed ($MODE). Restart Claude Code, then run /handoff."
