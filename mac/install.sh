#!/usr/bin/env bash
# Set up the OPTCG pack opener on macOS: a Python venv with PySide6 (+ PyObjC),
# and imagemagick / poppler for the pack/box photos and card backs.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v python3 >/dev/null; then
    echo "python3 not found -- install it first (e.g. 'brew install python')" >&2
    exit 1
fi

if command -v brew >/dev/null; then
    for pkg in imagemagick poppler; do
        brew list "$pkg" >/dev/null 2>&1 || brew install "$pkg"
    done
else
    echo "Homebrew not found: without imagemagick + poppler you get drawn packs/backs instead of the real ones."
fi

python3 -m venv "$DIR/.venv"
"$DIR/.venv/bin/pip" install -q --upgrade pip
"$DIR/.venv/bin/pip" install -q -r "$DIR/requirements.txt"
chmod +x "$DIR/optcg"

cat <<EOF

Installed. Try it:   $DIR/optcg        (run it again, or press Esc, to close)
                     $DIR/optcg box    (start with a booster box)

Hotkey: open the Shortcuts app -> New Shortcut -> "Run Shell Script" with
    $DIR/optcg
then in the shortcut's details choose "Add Keyboard Shortcut" (e.g. ⌘⇧P).
(skhd / Raycast / Hammerspoon work too -- just run that command.)
EOF
