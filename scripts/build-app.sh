#!/bin/bash
set -eo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRATCH="$RODNYE_BUILD_PATH"
if [ -z "$BUILD_SCRATCH" ]; then BUILD_SCRATCH="$PROJECT_ROOT/.build"; fi
cd "$PROJECT_ROOT"
swift build --configuration release --scratch-path "$BUILD_SCRATCH"
BIN_DIR="$(swift build --configuration release --scratch-path "$BUILD_SCRATCH" --show-bin-path)"
APP_PATH="$PROJECT_ROOT/build/Родные.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
# Replace the executable inode so an already running version keeps its mapped binary.
cp "$BIN_DIR/FamilyTree" "$APP_PATH/Contents/MacOS/FamilyTree.next"
mv -f "$APP_PATH/Contents/MacOS/FamilyTree.next" "$APP_PATH/Contents/MacOS/FamilyTree"
cp "$PROJECT_ROOT/scripts/Info.plist" "$APP_PATH/Contents/Info.plist"
ICON_DIR="$PROJECT_ROOT/build/AppIcon.iconset"
mkdir -p "$ICON_DIR"
swift "$PROJECT_ROOT/scripts/create-icon.swift" "$ICON_DIR"
iconutil -c icns "$ICON_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_PATH"
printf '%s\n' "Готово: $APP_PATH"
