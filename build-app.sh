#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
UNIVERSAL=1
BUILD_DMG=0
PREVIEW_UPDATES=0

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
    --preview-updates)
      PREVIEW_UPDATES=1
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

if [[ "$PREVIEW_UPDATES" -eq 1 ]]; then
  if [[ "$CONFIG" != "debug" ]]; then
    echo "Update UI preview requires --debug." >&2
    exit 1
  fi
  echo "▸ Preparing update preview from changelog.yaml..."
  if [[ ! -x build/release-python/bin/python ]]; then
    python3 -m venv build/release-python
  fi
  if ! build/release-python/bin/python -c 'import yaml; assert yaml.__version__ == "6.0.3"' 2>/dev/null; then
    build/release-python/bin/python -m pip install 'PyYAML==6.0.3'
  fi
  build/release-python/bin/python Tools/publish-updates.py --prepare-preview-notes
fi

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
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$STAGE/Contents/Frameworks/Sparkle.framework"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
cp assets/dynamic-island-notch.gif assets/dynamic-island-capsule.gif "$STAGE/Contents/Resources/" 2>/dev/null || true
find Resources -name "*.svg" -exec cp {} "$STAGE/Contents/Resources/" \; 2>/dev/null || true
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
if [[ "$PREVIEW_UPDATES" -eq 1 ]]; then
  cp build/UpdatePreviewNotes.json "$STAGE/Contents/Resources/UpdatePreviewNotes.json"
fi
if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$STAGE/Contents/Info.plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$STAGE/Contents/Info.plist"
fi
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$STAGE/Contents/Info.plist" >/dev/null
fi
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
  # Sign nested Sparkle code inside-out, preserving each helper's entitlements.
  SPARKLE_CONTENTS="$STAGE/Contents/Frameworks/Sparkle.framework/Versions/B"
  for helper in "$SPARKLE_CONTENTS"/XPCServices/*.xpc "$SPARKLE_CONTENTS"/Updater.app "$SPARKLE_CONTENTS"/Autoupdate; do
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements -s "$SIGN_IDENTITY" "$helper"
  done
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "$STAGE/Contents/Frameworks/Sparkle.framework"
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
    if xcrun stapler staple "$target" 2>&1 && xcrun stapler validate "$target"; then
      echo "✓ Stapling successful on attempt $attempt!"
      return 0
    fi
    echo "Stapler attempt $attempt/$max_attempts failed (thường do Apple CloudKit CDN chưa kịp đồng bộ ticket hoặc mạng chập chờn). Thử lại sau ${delay}s..."
    if [[ $attempt -lt $max_attempts ]]; then sleep "$delay"; fi
    attempt=$((attempt + 1))
    delay=$((delay + 5))
  done

  echo "Lỗi: Không thể staple và xác minh ticket cho $target sau $max_attempts lần thử." >&2
  return 1
}

notarize_and_staple() {
  local archive="$1"
  shift
  local result="build/notarization-result.json"
  echo "▸ Submitting $archive to Apple for Notarization..."
  if ! xcrun notarytool submit "$archive" "$@" --wait --output-format json > "$result"; then
    echo "Lỗi: Không hoàn tất yêu cầu notarization. Xem $result." >&2
    return 1
  fi
  python3 - "$result" <<'PY'
import json
import sys
with open(sys.argv[1]) as source:
    result = json.load(source)
if result.get("status") != "Accepted":
    raise SystemExit(f"Notarization rejected: status={result.get('status')}, id={result.get('id')}")
print(f"✓ Apple accepted notarization: {result.get('id')}")
PY
  staple_with_retry "$STAGE"
  staple_with_retry "$archive"
  codesign --verify --deep --strict "$STAGE"
  codesign --verify --strict "$archive"
  echo "✓ Notarization, stapling and signature verification completed!"
}

if [[ "$BUILD_DMG" -eq 1 ]]; then
  DMG_PATH="build/SenseBar.dmg"
  echo "▸ Packaging $DMG_PATH using SenseBar Professional DMG Designer..."
  swift Tools/MakeDMG.swift
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp -s "$SIGN_IDENTITY" "$DMG_PATH"

    # Notarize với Apple nếu có Apple ID + App-Specific Password
    if [[ -n "${APPLE_ID:-}" && -n "${APPLE_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
      notarize_and_staple "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID"
    elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
      notarize_and_staple "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE"
    fi
  fi
  echo "✓ DMG is ready at $DMG_PATH"
fi
