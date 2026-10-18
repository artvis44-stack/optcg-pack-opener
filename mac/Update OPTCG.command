#!/usr/bin/env bash
# Double-click in Finder to check for an OPTCG update right now.
# (Updates also install by themselves every few hours.)
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/.venv/bin/python" "$DIR/update.py"
echo
read -n 1 -s -r -p "Done -- press any key to close this window."
