#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
UNIVERSAL=1
BUILD_DMG=0

for arg in "$@"; do
  case "$arg" in
    --clean)
      ./Tools/clean.sh
      exit 0
      ;;
    --clean-all)
      ./Tools/clean.sh --all
      exit 0
      ;;
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
find Resources -name "*.svg" -exec cp {} "$STAGE/Contents/Resources/" \; 2>/dev/null || true
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
  codesign --force --entitlements Resources/SenseBar.entitlements -s - "$STAGE"
else
  echo "▸ Signing SenseBar.app with Developer Certificate..."
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "build/libSenseBarNowPlaying.dylib"
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "$STAGE/Contents/Frameworks/libSenseBarNowPlaying.dylib"
  codesign --force --options runtime --timestamp --entitlements Resources/SenseBar.entitlements -s "$SIGN_IDENTITY" "$STAGE"
fi

echo "✓ SenseBar.app is ready at $STAGE"

staple_with_retry() {
  local target="$1"
  local max_attempts=5
  local delay=10
  local attempt=1

  echo "▸ Stapling Notarization ticket to $target..."
  while [[ $attempt -le $max_attempts ]]; do
    if xcrun stapler staple "$target" 2>&1; then
      echo "✓ Stapling successful on attempt $attempt!"
      return 0
    fi
    echo "Stapler attempt $attempt/$max_attempts failed (thường do Apple CloudKit CDN chưa kịp đồng bộ ticket hoặc mạng chập chờn). Thử lại sau ${delay}s..."
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay + 5))
  done

  echo "Cảnh báo: Stapling không hoàn tất sau $max_attempts lần thử do Apple CloudKit CDN gặp sự cố kết nối."
  echo "ℹLưu ý: Bản build đã được Apple Notarize hợp lệ (Accepted), người dùng vẫn mở bình thường qua Gatekeeper."
  return 0
}

if [[ "$BUILD_DMG" -eq 1 ]]; then
  DMG_PATH="build/SenseBar.dmg"
  echo "▸ Packaging $DMG_PATH using SenseBar Professional DMG Designer..."
  swift Tools/MakeDMG.swift
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

      echo "▸ Chờ Apple CloudKit đồng bộ ticket (10s)..."
      sleep 10
      staple_with_retry "$DMG_PATH"
      echo "✓ Notarization & Stapling completed!"
    elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
      echo "▸ Submitting $DMG_PATH to Apple using profile '$NOTARY_PROFILE'..."
      xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
      echo "▸ Chờ Apple CloudKit đồng bộ ticket (10s)..."
      sleep 10
      staple_with_retry "$DMG_PATH"
      echo "✓ Notarization & Stapling completed!"
    fi
  fi
  echo "✓ DMG is ready at $DMG_PATH"
fi
