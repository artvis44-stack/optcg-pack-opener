#!/usr/bin/env bash
# Set up the OPTCG pack opener on macOS: a Python venv with PySide6 (+ PyObjC),
# imagemagick / poppler for the pack/box photos and card backs, and two login
# items: the desktop showcase, and the auto-updater (checks GitHub every 6 h).
#
# PySide6 needs macOS 13+ and Python 3.10+. macOS's own python3 (from the
# Command Line Tools) is 3.9, so this uses Homebrew's Python instead.
#
# usage: install.sh                 full install (safe to rerun)
#        install.sh --agents-only   just rewrite the login items (the updater uses this)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$HOME/Library/LaunchAgents"

write_agent() {   # label, then the program arguments; extra plist keys come in on stdin
    local label="$1"; shift
    local args=""
    for a in "$@"; do args+="        <string>$a</string>"$'\n'; done
    mkdir -p "$AGENTS"
    cat > "$AGENTS/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array>
$args    </array>
    <key>RunAtLoad</key><true/>
$(cat)
</dict>
</plist>
PLIST
}

write_agents() {
    # the desktop showcase after a restart (exits right away if no card is picked)
    write_agent com.optcg.showcase "$DIR/.venv/bin/python" "$DIR/optcg.py" "--showcase" </dev/null
    # the auto-updater: at login and every 6 hours
    write_agent com.optcg.updater "$DIR/.venv/bin/python" "$DIR/update.py" <<'KEYS'
    <key>StartInterval</key><integer>21600</integer>
KEYS
}

if [ "${1:-}" = "--agents-only" ]; then
    write_agents
    exit 0
fi

macos="$(sw_vers -productVersion)"
if [ "${macos%%.*}" -lt 13 ]; then
    echo "This needs macOS 13 (Ventura) or newer -- this Mac has $macos." >&2
    exit 1
fi

if ! command -v brew >/dev/null; then
    cat >&2 <<'EOF'
Homebrew isn't installed. Install it with:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
follow its "Next steps", open a new Terminal window, and run this installer again.
EOF
    exit 1
fi

for pkg in python imagemagick poppler; do
    brew list "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done

PY="$(brew --prefix)/bin/python3"
if ! "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
    echo "Homebrew's Python is too old ($("$PY" --version)); run 'brew upgrade python' and try again." >&2
    exit 1
fi

rm -rf "$DIR/.venv"   # start clean (an earlier attempt may have used the wrong Python)
"$PY" -m venv "$DIR/.venv"
"$DIR/.venv/bin/pip" install --upgrade pip
"$DIR/.venv/bin/pip" install -r "$DIR/requirements.txt"
"$DIR/.venv/bin/python" -c "import PySide6; print('PySide6', PySide6.__version__, 'OK')"
chmod +x "$DIR/optcg" "$DIR/update.py" "$DIR/Update OPTCG.command"

write_agents
# start the updater now rather than at the next login
launchctl bootout "gui/$(id -u)/com.optcg.updater" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENTS/com.optcg.updater.plist" || true

cat <<EOF

Installed. Try it:   $DIR/optcg        (run it again, or press Esc, to close)
                     $DIR/optcg box    (start with a booster box)

Updates install themselves (checked at login and every 6 hours; log in
~/Library/Logs/optcg-update.log). To check right now, double-click
"Update OPTCG" in $DIR in Finder.

Hotkey: open the Shortcuts app -> New Shortcut -> "Run Shell Script" with
    $DIR/optcg
then in the shortcut's details choose "Add Keyboard Shortcut" (e.g. ⌃⌥P).
(skhd / Raycast / Hammerspoon work too -- just run that command.)
EOF
