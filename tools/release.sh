#!/usr/bin/env bash
# Publish a release: push, tag, bundle, GitHub release (the Mac auto-updater
# picks it up within a few hours).
# usage: tools/release.sh v1.3.0 "What changed"
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
tag="${1:?usage: tools/release.sh vX.Y.Z \"notes\"}"
notes="${2:-}"
PATH="$HOME/.local/bin:$PATH"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "commit your changes first" >&2
    exit 1
fi
git push -q origin main:pack-opener
git tag -a "$tag" -m "OPTCG pack opener ${tag#v}"   # tag first, so the bundle contains it
git push -q origin "$tag"
tmp="$(mktemp -d)"
git bundle create "$tmp/optcg.bundle" --all
cp "$tmp/optcg.bundle" "$HOME/optcg.bundle"
gh release create "$tag" "$tmp/optcg.bundle#optcg.bundle (git repo, all history)" \
    --title "OPTCG pack opener ${tag#v}" --notes "$notes" --verify-tag
rm -rf "$tmp"
