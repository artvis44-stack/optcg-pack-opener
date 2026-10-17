#!/usr/bin/env bash
# Recompile shaders/*.frag -> *.frag.qsb (needs qt6-shadertools)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/app/shaders"
QSB=$(command -v qsb || echo /usr/lib/qt6/bin/qsb)
for f in *.frag; do
    "$QSB" --qt6 -o "$f.qsb" "$f"
    echo "built $f.qsb"
done
