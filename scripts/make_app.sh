#!/bin/bash
# swift build の成果物から build/Panely.app を組み立てて署名する。
# LSUIElement を効かせるには .app バンドルが必要で、swift run では確認できない。
#
# 使い方: scripts/make_app.sh
#   署名 ID は CODESIGN_IDENTITY で指定できる。未指定ならキーチェーンの "Apple Development" を使い、
#   無ければ ad-hoc の "-" にする。ad-hoc はビルドごとに cdhash が変わり、
#   TCC が別アプリとみなしてアクセシビリティ許可がリセットされる。
#   APP_VERSION（例: 0.2.0）と APP_BUILD（例: 42）を渡すと Info.plist の版数を上書きする。CI のリリース用。
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Panely"
APP_DIR="build/${APP_NAME}.app"

find_identity() {
  security find-identity -v -p codesigning | awk '/Apple Development/ { print $2; exit }'
}
IDENTITY="${CODESIGN_IDENTITY:-$(find_identity)}"
IDENTITY="${IDENTITY:--}"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "${APP_NAME}-Info.plist" "$APP_DIR/Contents/Info.plist"
cp Assets/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
if [[ -n "${APP_VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP_DIR/Contents/Info.plist"
fi
if [[ -n "${APP_BUILD:-}" ]]; then
  plutil -replace CFBundleVersion -string "$APP_BUILD" "$APP_DIR/Contents/Info.plist"
fi

codesign --force --sign "$IDENTITY" "$APP_DIR"

echo "署名 ID: $IDENTITY"
echo "作成: $APP_DIR"
echo "起動: open $APP_DIR"
