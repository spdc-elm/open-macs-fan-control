#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
EXECUTABLE="$BUILD_DIR/fan-control-menu-bar"
APP_DIR="$ROOT_DIR/dist/MacsFanControlMenuBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
PLIST_SOURCE="$ROOT_DIR/packaging/fan-control-menu-bar/Info.plist"

swift build --product fan-control-menu-bar --product fan-control-controller

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/fan-control-menu-bar"
cp "$BUILD_DIR/fan-control-controller" "$MACOS_DIR/fan-control-controller"
cp "$PLIST_SOURCE" "$CONTENTS_DIR/Info.plist"

chmod +x "$MACOS_DIR/fan-control-menu-bar"
chmod +x "$MACOS_DIR/fan-control-controller"

printf 'Packaged app at %s\n' "$APP_DIR"
