#!/usr/bin/env bash
# Toggle the OPTCG pack opener. Downloads card data on first run.
DIR="$(dirname "$(readlink -f "$0")")"
SET="${OPTCG_SET:-OP-17}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/optcg/$SET"

# already open -> close it (the IPC call only succeeds if an instance is running)
if qs ipc -p "$DIR" call optcg close >/dev/null 2>&1; then
    exit 0
fi

if [ ! -f "$CACHE/cards.json" ] || [ ! -f "$CACHE/../assets/back_don.png" ]; then
    notify-send "OPTCG" "Downloading $SET cards (first run)…"
    if ! python3 -I "$DIR/fetch_cards.py" "$SET"; then
        notify-send -u critical "OPTCG" "Couldn't download $SET card data"
        exit 1
    fi
fi

# the binder saves to $XDG_DATA_HOME/optcg/collection.json
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/optcg"

exec qs -n -p "$DIR"
