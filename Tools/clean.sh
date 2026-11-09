#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "🧹 Đang dọn dẹp môi trường test và các file build rác của SenseBar..."

# 1. Tắt ứng dụng nếu đang chạy
if pgrep -x "SenseBar" >/dev/null 2>&1; then
  echo "▸ Tắt tiến trình SenseBar đang chạy..."
  killall SenseBar 2>/dev/null || true
  sleep 0.5
fi

# 2. Tháo gỡ các ổ đĩa ảo DMG nếu còn gắn
if [[ -d "/Volumes/SenseBar" ]]; then
  echo "▸ Tháo gỡ đĩa ảo /Volumes/SenseBar..."
  hdiutil detach "/Volumes/SenseBar" -force 2>/dev/null || true
fi

# 3. Xoá thư mục build và cache SPM
echo "▸ Xoá thư mục build/ và .build/..."
rm -rf build .build

# 4. Xoá file Preferences và Cache lưu trên máy
echo "▸ Xoá cài đặt UserDefaults và Cache..."
defaults delete com.sensebar.SenseBar 2>/dev/null || true
rm -f ~/Library/Preferences/com.sensebar.SenseBar.plist
rm -rf ~/Library/Caches/com.sensebar.SenseBar
rm -rf ~/Library/Saved\ Application\ State/com.sensebar.SenseBar.savedState

# 5. Nếu truyền tham số --all hoặc --tcc, thu hồi luôn quyền Trợ năng (Accessibility)
if [[ "${1:-}" == "--all" || "${1:-}" == "--tcc" ]]; then
  echo "▸ Đặt lại quyền hệ thống (TCC Accessibility)..."
  tccutil reset All com.sensebar.SenseBar 2>/dev/null || true
fi

echo "✨ Hoàn tất! Mã nguồn và máy của bạn đã sạch sẽ hoàn toàn 100%."

