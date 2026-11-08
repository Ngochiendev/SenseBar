# SenseBar

<p align="center">
  <img src="Resources/Brand/AppIcon-Default.png" width="128" height="128" alt="SenseBar Logo">
</p>

<p align="center">
  <strong>Tiện ích thanh Menu Bar gọn nhẹ cho macOS</strong><br>
  Tai thỏ Dynamic Island · Bộ trộn âm thanh từng ứng dụng (Audio Studio)
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-blue?style=flat-square" alt="Apple Silicon & Intel">
  <img src="https://img.shields.io/badge/Language-Swift%206%20%7C%20SwiftUI-orange?style=flat-square&logo=swift" alt="Swift 6 & SwiftUI">
  <img src="https://img.shields.io/badge/License-GPL--3.0-green?style=flat-square" alt="License">
</p>

---

## Giới thiệu

**SenseBar** là tiện ích hệ thống thế hệ mới dành cho macOS, tối ưu hiệu năng siêu nhẹ và tập trung vào 2 nhóm tính năng cốt lõi:

1. **Tai thỏ & Dynamic Island**: Biến phần tai thỏ MacBook hoặc cạnh trên màn hình thành khu vực điều khiển nhanh đa phương tiện, tích hợp sóng nhạc chuyển động và cử chỉ cuộn chuột tăng giảm âm lượng/độ sáng.
2. **Bộ trộn âm thanh (Audio Studio)**: Điều chỉnh âm lượng độc lập cho từng ứng dụng (0% – 200%), chuyển đổi tức thì thiết bị Loa/Micro và tự động ngắt tiếng bảo vệ thính giác khi rút tai nghe.

> 💡 **Khả năng thích ứng màn hình thông minh**:
> - Trên các dòng máy có tai thỏ (MacBook Air/Pro Apple Silicon): Giao diện tự động ôm khít tai thỏ vật lý.
> - Trên các dòng máy **không có tai thỏ** (toàn bộ **Mac Intel**, Mac mini, Mac Studio, iMac hoặc khi sử dụng **màn hình rời ngoài**): SenseBar tự động hiển thị dưới dạng **Viên nang nổi (Floating Capsule)** thanh thoát, đầy đủ mọi tính năng.

---

## Khả năng tương thích

- **Kiến trúc phần cứng**: Bản build **Universal Binary** chạy Native mượt mà trên cả hai nền tảng:
  - **Apple Silicon**: M1, M2, M3, M4 (Bản thường, Pro, Max, Ultra).
  - **Intel Mac**: Toàn bộ máy Mac chạy chip Intel 64-bit (`x86_64`) mà không cần giả lập qua Rosetta 2.
- **Hệ điều hành yêu cầu**: **macOS 14.0 (Sonoma)** trở lên.

---

## Các tính năng chính

### 1. Tai thỏ & Dynamic Island
* **Trình phát nhạc (Now Playing)**: Tự động bắt thông tin bài hát đang phát (Apple Music, Spotify, Chrome, YouTube...), hiển thị ảnh bìa album và các nút điều khiển chuyển bài nhanh.
* **Sóng nhạc (Audio Visualizer)**: Hiệu ứng sóng âm sống động theo điệu nhạc, tự động trích xuất màu sắc chủ đạo từ ảnh bìa đĩa.
* **Cuộn chuột chỉnh nhanh**: Rê chuột lên vùng tai thỏ / viên nang và cuộn con lăn để tăng giảm nhanh âm lượng hoặc độ sáng màn hình.
* **Hiệu ứng Liquid Glass**: Giao diện kính mờ xuyên thấu tinh tế chuẩn phong cách macOS nguyên bản.

### 2. Bộ trộn âm thanh (Audio Studio)
* **Âm lượng từng ứng dụng**: Tăng/giảm âm lượng độc lập cho từng ứng dụng đang chạy (Safari, Chrome, Spotify, Discord...) mà không cần cài thêm kext hay driver âm thanh ngoài.
* **Khuếch đại âm lượng đến 200%**: Tăng âm lượng vượt ngưỡng mặc định cho các cuộc gọi hoặc video có âm thanh gốc quá nhỏ.
* **Đổi nhanh Loa / Micro & Tắt nhanh Micro**: Chuyển đổi thiết bị đầu ra/đầu vào tức thì và ngắt nhanh micro toàn hệ thống.
* **An toàn tai nghe (Headphone Safety)**: Tự động ngắt âm lượng loa ngoài khi ngắt kết nối tai nghe (jack 3.5mm hoặc Bluetooth) đột ngột.

---

## Cài đặt nhanh

Tải bản phát hành chính thức dạng file `.dmg` tại [GitHub Releases](https://github.com/Ngochiendev/SenseBar/releases):

1. Tải file **`SenseBar-vX.X.X-macOS-Universal.dmg`**.
2. Mở file `.dmg` và kéo biểu tượng **SenseBar** vào thư mục **Applications**.
3. Khởi chạy SenseBar từ Launchpad hoặc Spotlight, sau đó cấp quyền **Trợ năng (Accessibility)** để trải nghiệm đầy đủ các tính năng điều khiển.

---

## Dành cho nhà phát triển (Build từ mã nguồn)

Yêu cầu môi trường: **macOS 14.0+**, **Xcode Command Line Tools** (hỗ trợ Swift 6).

```bash
# 1. Clone mã nguồn dự án
git clone https://github.com/Ngochiendev/SenseBar.git
cd SenseBar

# 2. Biên dịch và đóng gói SenseBar.app (Universal Binary)
./build-app.sh

# 3. Chạy thử nghiệm ứng dụng
open build/SenseBar.app
```

---

## Giấy phép

Dự án được phân phối dưới giấy phép **GNU General Public License v3.0 (GPL-3.0)** — xem chi tiết tại file [LICENSE](LICENSE).
