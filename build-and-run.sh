#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_PATH="$SCRIPT_DIR/Kanban Sticky.app"
CONTENTS="$APP_PATH/Contents"
BINARY_PATH="$CONTENTS/MacOS/KanbanSticky"
USER_APPLICATIONS_DIR="$HOME/Applications"
INSTALL_PATH="$USER_APPLICATIONS_DIR/Kanban Sticky.app"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
swiftc "$SCRIPT_DIR/KanbanSticky.swift" \
    -o "$BINARY_PATH" \
    -framework AppKit \
    -framework SwiftUI
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$BINARY_PATH"
codesign --force --deep --sign - "$APP_PATH" >/dev/null

mkdir -p "$USER_APPLICATIONS_DIR"
if [[ -d "$INSTALL_PATH" ]]; then
    osascript -e 'tell application "Kanban Sticky" to quit' >/dev/null 2>&1 || true
    pkill -x KanbanSticky >/dev/null 2>&1 || true
    sleep 0.7
    rm -rf "$INSTALL_PATH"
fi
ditto "$APP_PATH" "$INSTALL_PATH"
open "$INSTALL_PATH"

echo "Kanban Sticky terpasang dan berjalan dari: $INSTALL_PATH"
