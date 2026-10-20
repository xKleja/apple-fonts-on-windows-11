#!/bin/bash
# macOS only. Downloads Apple's official font installers from developer.apple.com, refuses any
# package not signed by Apple, and extracts the fonts into the layout the installer expects:
#   <out>/SF Pro, SF Compact, SF Mono, New York, SF Multilingual Extensions/SF {Arabic,Armenian,Georgian,Hebrew}
#
# Usage: build/fetch_apple_fonts.sh <out dir>        (e.g. build/work/SF)
set -euo pipefail
OUT=${1:?usage: fetch_apple_fonts.sh <out dir>}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
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
  curl -fsSL -o "$WORK/$dmg.dmg" "$BASE/$dmg.dmg"
  mnt=$(mktemp -d)
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mnt" "$WORK/$dmg.dmg"
  for pkg in "$mnt"/*.pkg; do
    sig=$(pkgutil --check-signature "$pkg" | sed -n 2p)
    echo "   $(basename "$pkg"): $sig"
    case "$sig" in *"signed Apple Software"*) ;; *) hdiutil detach -quiet "$mnt"; echo "NOT SIGNED BY APPLE: $pkg"; exit 1;; esac
    pkgutil --expand-full "$pkg" "$WORK/x-$dmg" >/dev/null
  done
  hdiutil detach -quiet "$mnt"
  mkdir -p "$OUT/$dest"
  find "$WORK/x-$dmg" -type f \( -name '*.ttf' -o -name '*.otf' \) -exec cp {} "$OUT/$dest/" \;
done

echo "== $(find "$OUT" -type f \( -name '*.ttf' -o -name '*.otf' \) | wc -l | tr -d ' ') fonts in $OUT (expected 155)"
