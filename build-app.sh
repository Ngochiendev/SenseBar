#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
UNIVERSAL=1
BUILD_DMG=0

for arg in "$@"; do
  case "$arg" in
    --debug)
      CONFIG="debug"
      UNIVERSAL=0
      ;;
    --release)
      CONFIG="release"
      ;;
    --native)
      UNIVERSAL=0
      ;;
    --universal)
      UNIVERSAL=1
      ;;
    --dmg)
      CONFIG="release"
      UNIVERSAL=1
      BUILD_DMG=1
      ;;
  esac
done

ARCH_FLAGS=()
if [[ "$UNIVERSAL" -eq 1 ]]; then
  echo "▸ Compiling SenseBar ($CONFIG, Universal: arm64 + x86_64)..."
  swift build -c "$CONFIG" --arch arm64
  swift build -c "$CONFIG" --arch x86_64

  ARM_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
  INTEL_DIR="$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)"
  BIN_DIR="build/universal-bin"
  mkdir -p "$BIN_DIR"

  lipo -create -output "$BIN_DIR/SenseBar" "$ARM_DIR/SenseBar" "$INTEL_DIR/SenseBar"
  lipo -create -output "$BIN_DIR/libSenseBarNowPlaying.dylib" "$ARM_DIR/libSenseBarNowPlaying.dylib" "$INTEL_DIR/libSenseBarNowPlaying.dylib"
else
  echo "▸ Compiling SenseBar ($CONFIG, Native)..."
  swift build -c "$CONFIG"
  BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
fi

echo "▸ Generating SenseBar icons..."
mkdir -p build
if [[ ! -f "build/AppIcon.icns" || ! -f "build/MenuBarIcon@2x.png" ]]; then
  swift Tools/MakeIcon.swift build/AppIcon.iconset
fi

echo "▸ Assembling SenseBar.app..."
STAGE="build/SenseBar.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" "$STAGE/Contents/Frameworks"

cp "$BIN_DIR/SenseBar" "$STAGE/Contents/MacOS/SenseBar"
cp "$BIN_DIR/libSenseBarNowPlaying.dylib" "$STAGE/Contents/Frameworks/libSenseBarNowPlaying.dylib"
cp "$BIN_DIR/libSenseBarNowPlaying.dylib" "build/libSenseBarNowPlaying.dylib"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

# Xoá các thuộc tính mở rộng / quarantine thừa trước khi ký
xattr -cr "$STAGE" "build/libSenseBarNowPlaying.dylib" 2>/dev/null || true

# Tự động phát hiện chứng chỉ Developer ID Application nếu chưa truyền SIGN_IDENTITY
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  DETECTED_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
  SIGN_IDENTITY="${DETECTED_ID:--}"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "▸ Signing SenseBar.app (Ad-hoc signature)..."
  codesign --force -s - "build/libSenseBarNowPlaying.dylib"
  codesign --force -s - "$STAGE/Contents/Frameworks/libSenseBarNowPlaying.dylib"
  codesign --force -s - "$STAGE"
else
  echo "▸ Signing SenseBar.app with Developer Certificate..."
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "build/libSenseBarNowPlaying.dylib"
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "$STAGE/Contents/Frameworks/libSenseBarNowPlaying.dylib"
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "$STAGE"
fi

echo "✓ SenseBar.app is ready at $STAGE"

if [[ "$BUILD_DMG" -eq 1 ]]; then
  DMG_PATH="build/SenseBar.dmg"
  DMG_ROOT="build/dmg-root"
  echo "▸ Packaging $DMG_PATH..."
  rm -rf "$DMG_ROOT" "$DMG_PATH"
  mkdir -p "$DMG_ROOT"
  cp -R "$STAGE" "$DMG_ROOT/SenseBar.app"
  ln -s /Applications "$DMG_ROOT/Applications"
  hdiutil create -volname "SenseBar" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$DMG_ROOT"
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp -s "$SIGN_IDENTITY" "$DMG_PATH"

    # Notarize với Apple nếu có Apple ID + App-Specific Password
    if [[ -n "${APPLE_ID:-}" && -n "${APPLE_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
      echo "▸ Submitting $DMG_PATH to Apple for Notarization..."
      xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

      echo "▸ Stapling Notarization ticket to $DMG_PATH..."
      xcrun stapler staple "$DMG_PATH"
      echo "✓ Notarization & Stapling completed successfully!"
    elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
      echo "▸ Submitting $DMG_PATH to Apple using profile '$NOTARY_PROFILE'..."
      xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
      echo "▸ Stapling Notarization ticket to $DMG_PATH..."
      xcrun stapler staple "$DMG_PATH"
      echo "✓ Notarization & Stapling completed successfully!"
    fi
  fi
  echo "✓ DMG is ready at $DMG_PATH"
fi
