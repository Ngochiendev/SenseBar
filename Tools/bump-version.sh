#!/bin/zsh
set -euo pipefail

# Script tự động nâng version và build number trong Resources/Info.plist
# Hỗ trợ: patch (mặc định), minor, major, hoặc truyền version cụ thể (vd: 1.0.2)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST_FILE="$PROJECT_DIR/Resources/Info.plist"

if [[ ! -f "$PLIST_FILE" ]]; then
  echo "❌ Lỗi: Không tìm thấy file $PLIST_FILE" >&2
  exit 1
fi

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_FILE" 2>/dev/null || echo "1.0.0")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_FILE" 2>/dev/null || echo "1")

# Đọc mode / version mới từ đối số
ARG="${1:-patch}"

if [[ "$ARG" == "current" || "$ARG" == "--current" || "$ARG" == "-v" ]]; then
  echo "📌 SenseBar hiện tại: v$CURRENT_VERSION (Build $CURRENT_BUILD)"
  exit 0
fi

# Tách semantic version: MAJOR.MINOR.PATCH
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR="${MAJOR:-1}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

# Xử lý nếu PATCH có hậu tố (như 1-beta)
PATCH_NUM=$(echo "$PATCH" | sed 's/[^0-9].*//')
PATCH_NUM="${PATCH_NUM:-0}"

case "$ARG" in
  patch)
    NEW_PATCH=$((PATCH_NUM + 1))
    NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
    ;;
  minor)
    NEW_MINOR=$((MINOR + 1))
    NEW_VERSION="$MAJOR.$NEW_MINOR.0"
    ;;
  major)
    NEW_MAJOR=$((MAJOR + 1))
    NEW_VERSION="$NEW_MAJOR.0.0"
    ;;
  *)
    # Người dùng truyền version tuỳ chỉnh trực tiếp (vd: 1.0.2)
    NEW_VERSION="$ARG"
    # Xoá tiền tố 'v' nếu lỡ gõ v1.0.2
    NEW_VERSION="${NEW_VERSION#v}"
    ;;
esac

NEW_BUILD=$((CURRENT_BUILD + 1))

# Cập nhật Info.plist bằng PlistBuddy
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST_FILE"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST_FILE"

echo "=================================================="
echo "🚀 Đã nâng phiên bản SenseBar thành công!"
echo "   • Phiên bản : $CURRENT_VERSION  ➜  $NEW_VERSION"
echo "   • Build num : $CURRENT_BUILD  ➜  $NEW_BUILD"
echo "   • File      : Resources/Info.plist"
echo "=================================================="
echo ""
echo "💡 Các bước tiếp theo:"
echo "   1. Kiểm tra git diff:  git diff Resources/Info.plist"
echo "   2. Tạo commit:         git commit -am \"chore: bump version to v$NEW_VERSION (build $NEW_BUILD)\""
echo "   3. Khi merge vào 'main', GitHub Actions sẽ tự động phát hành SenseBar-v$NEW_VERSION.dmg!"

