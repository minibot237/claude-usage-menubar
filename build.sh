#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/ClaudeUsage.app"

echo "Building Claude Usage..."

# Clean previous build
rm -rf "$APP"

# Create bundle structure
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Compile
swiftc -o "$APP/Contents/MacOS/claude-usage" \
	"$SCRIPT_DIR/main.swift" \
	-framework Cocoa \
	-framework WebKit \
	-O \
	-suppress-warnings

# Copy source into Resources for easy rebuilds
cp "$SCRIPT_DIR/main.swift" "$APP/Contents/Resources/"

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP/Contents/"

# Ad-hoc codesign
codesign --force --sign - "$APP"

echo "Built: $APP"
echo ""
echo "Install:  cp -r ClaudeUsage.app /Applications/"
echo "Run:      open ClaudeUsage.app"
