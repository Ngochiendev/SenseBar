#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling SenseBar..."
swift build

echo "Generating SenseBar icons..."
mkdir -p build
swift Tools/MakeIcon.swift build/AppIcon.iconset

echo "▸ Assembling SenseBar.app..."
STAGE="build/SenseBar.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp .build/arm64-apple-macosx/debug/SenseBar "$STAGE/Contents/MacOS/SenseBar"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

echo "Signing SenseBar.app..."
codesign -s - --force --deep "$STAGE"

echo "SenseBar.app is ready at build/SenseBar.app"
