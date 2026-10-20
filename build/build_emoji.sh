#!/bin/bash
# macOS only. Builds AppleColorEmoji-Windows.ttf from this Mac's own Apple Color Emoji using
# samuelngs/apple-emoji-ttf (the "Windows" recipe: names/metrics of Segoe UI Emoji, CBDT bitmaps).
#
# Usage: build/build_emoji.sh <out dir> [apple-emoji-ttf git ref]
# Needs: git, uv (brew install uv)
set -euo pipefail
OUT=${1:?usage: build_emoji.sh <out dir> [git ref]}
REF=${2:-484daf4e13942437e083d881cae39fbc92d837e1}   # the commit used for the current release
SRC="/System/Library/Fonts/Apple Color Emoji.ttc"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "macOS $(sw_vers -productVersion), emoji font: $(stat -f '%Sm' "$SRC")"
git clone -q https://github.com/samuelngs/apple-emoji-ttf.git "$WORK/repo"
git -C "$WORK/repo" checkout -q "$REF"
cd "$WORK/repo"
uv venv -q --python "$(cat .python-version)" .venv
uv pip install -q --python .venv/bin/python -r requirements.txt
# --update-sequences: take the newest Unicode emoji sequence data, so every emoji Apple draws is mapped.
.venv/bin/python cli.py -c configs/windows.yaml --input "$SRC" \
    --output output/AppleColorEmoji-Windows.ttf --update-sequences
mkdir -p "$OUT"
cp output/AppleColorEmoji-Windows.ttf "$OUT/"
cp sequences/emoji-test.txt "$OUT/emoji-test.txt"   # for build/emoji_coverage.py
echo "== $OUT/AppleColorEmoji-Windows.ttf"
