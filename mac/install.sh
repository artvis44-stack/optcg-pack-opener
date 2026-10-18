#!/usr/bin/env bash
# Set up the OPTCG pack opener on macOS: a Python venv with PySide6 (+ PyObjC),
# and imagemagick / poppler for the pack/box photos and card backs.
#
# PySide6 needs macOS 13+ and Python 3.10+. macOS's own python3 (from the
# Command Line Tools) is 3.9, so this uses Homebrew's Python instead.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

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
chmod +x "$DIR/optcg"

# bring the desktop showcase back after a restart (it exits right away if no card is picked)
AGENT="$HOME/Library/LaunchAgents/com.optcg.showcase.plist"
mkdir -p "$(dirname "$AGENT")"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.optcg.showcase</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DIR/.venv/bin/python</string>
        <string>$DIR/optcg.py</string>
        <string>--showcase</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST

cat <<EOF

Installed. Try it:   $DIR/optcg        (run it again, or press Esc, to close)
                     $DIR/optcg box    (start with a booster box)

Hotkey: open the Shortcuts app -> New Shortcut -> "Run Shell Script" with
    $DIR/optcg
then in the shortcut's details choose "Add Keyboard Shortcut" (e.g. ⌃⌥P).
(skhd / Raycast / Hammerspoon work too -- just run that command.)
EOF
