#!/usr/bin/env bash
# macOS only. Downloads Apple's official font installers from developer.apple.com, refuses any
# package not signed by Apple, and extracts the fonts into the layout the installer expects:
#   <out>/SF Pro, SF Compact, SF Mono, New York, SF Multilingual Extensions/SF {Arabic,Armenian,Georgian,Hebrew}
#
# Usage: build/fetch_apple_fonts.sh <out dir>        (e.g. build/work/SF)
set -euo pipefail
[ "$(uname)" = Darwin ] || { echo "fetch_apple_fonts.sh runs on macOS only" >&2; exit 1; }
OUT=${1:?usage: fetch_apple_fonts.sh <out dir>}
EXPECTED=155
if [ -d "$OUT" ] && [ -n "$(find "$OUT" -type f \( -name '*.ttf' -o -name '*.otf' \) -print -quit)" ]; then
  echo "$OUT already contains fonts; pass an empty or new directory" >&2; exit 1
fi
WORK=$(mktemp -d)
MNT=""
cleanup() {
  if [ -n "$MNT" ]; then hdiutil detach -quiet "$MNT" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
BASE=https://devimages-cdn.apple.com/design/resources/download

# dmg name -> folder in the output
declare -a MAP=(
  "SF-Pro:SF Pro" "SF-Compact:SF Compact" "SF-Mono:SF Mono" "NY:New York"
  "SF-Arabic:SF Multilingual Extensions/SF Arabic" "SF-Armenian:SF Multilingual Extensions/SF Armenian"
  "SF-Georgian:SF Multilingual Extensions/SF Georgian" "SF-Hebrew:SF Multilingual Extensions/SF Hebrew"
)

for entry in "${MAP[@]}"; do
  dmg=${entry%%:*}; dest=${entry#*:}
  echo "== $dmg"
  curl -fsSL --retry 3 --connect-timeout 20 --max-time 900 -o "$WORK/$dmg.dmg" "$BASE/$dmg.dmg"
  MNT=$(mktemp -d)
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$WORK/$dmg.dmg"
  found=0
  for pkg in "$MNT"/*.pkg; do
    [ -e "$pkg" ] || continue
    found=1
    sig=$(pkgutil --check-signature "$pkg" | sed -n 2p)
    echo "   $(basename "$pkg"): $sig"
    case "$sig" in *"signed Apple Software"*) ;; *) echo "NOT SIGNED BY APPLE: $pkg" >&2; exit 1;; esac
    pkgutil --expand-full "$pkg" "$WORK/x-$dmg-$(basename "$pkg" .pkg)" >/dev/null
  done
  [ "$found" = 1 ] || { echo "No .pkg found in $dmg.dmg" >&2; exit 1; }
  hdiutil detach -quiet "$MNT"
  MNT=""
  mkdir -p "$OUT/$dest"
  # -n: two packages shipping the same file name is an error, not a silent overwrite
  find "$WORK" -path "$WORK/x-$dmg-*" -type f \( -name '*.ttf' -o -name '*.otf' \) -print0 |
    while IFS= read -r -d '' f; do
      t="$OUT/$dest/$(basename "$f")"
      [ ! -e "$t" ] || { echo "Duplicate font file name: $t" >&2; exit 1; }
      cp "$f" "$t"
    done
done

n=$(find "$OUT" -type f \( -name '*.ttf' -o -name '*.otf' \) | wc -l | tr -d ' ')
echo "== $n fonts in $OUT (expected $EXPECTED)"
[ "$n" -eq "$EXPECTED" ] || { echo "Unexpected font count: $n (expected $EXPECTED)" >&2; exit 1; }
