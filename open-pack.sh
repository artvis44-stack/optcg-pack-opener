#!/usr/bin/env bash
# Toggle the OPTCG pack opener. Downloads card data on first run.
# usage: open-pack.sh [box]   ("box" starts in booster box mode)
DIR="$(dirname "$(readlink -f "$0")")"

# already open -> close it (the IPC call only succeeds if an instance is running)
if qs ipc -p "$DIR" call optcg close >/dev/null 2>&1; then
    exit 0
fi

# card data is downloaded by the app itself (first run, or when picking a new set)
# the binder saves to $XDG_DATA_HOME/optcg/collection.json
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/optcg"

[ "$1" = "box" ] && export OPTCG_MODE=box
exec qs -n -p "$DIR"
