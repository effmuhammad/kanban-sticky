#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_PATH="$SCRIPT_DIR/Kanban Sticky.app"
OUTPUT_DIR="$SCRIPT_DIR/dist"
DMG_PATH="$OUTPUT_DIR/Kanban-Sticky-1.0.dmg"
STAGING_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$OUTPUT_DIR"
swiftc "$SCRIPT_DIR/KanbanSticky.swift" \
    -o "$APP_PATH/Contents/MacOS/KanbanSticky" \
    -framework AppKit \
    -framework SwiftUI
cp "$SCRIPT_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
chmod +x "$APP_PATH/Contents/MacOS/KanbanSticky"
codesign --force --deep --sign - "$APP_PATH" >/dev/null

ditto "$APP_PATH" "$STAGING_DIR/Kanban Sticky.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "Kanban Sticky" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "Installer berhasil dibuat: $DMG_PATH"
