#!/bin/bash
# Assets/AppIcon.svg から Assets/AppIcon.icns を生成する。
# 生成物はコミットする。CI のランナーに SVG 変換ツールが無くても .app を組み立てられるようにするため。
#
# 使い方: scripts/make_icon.sh
#   SVG の描画には rsvg-convert（brew install librsvg）を使う。無ければ qlmanage で代用する。
set -euo pipefail

cd "$(dirname "$0")/.."

SVG="Assets/AppIcon.svg"
ICNS="Assets/AppIcon.icns"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
MASTER="$WORK/master.png"
trap 'rm -rf "$WORK"' EXIT

if command -v rsvg-convert >/dev/null; then
  rsvg-convert -w 1024 -h 1024 "$SVG" -o "$MASTER"
else
  qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null
  mv "$WORK/$(basename "$SVG").png" "$MASTER"
fi

mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "作成: $ICNS"
