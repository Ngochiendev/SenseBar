# SenseBar

<p align="center">
  <img src="Resources/Brand/AppIcon-Default.png" width="128" height="128" alt="SenseBar Logo">
</p>

<p align="center">
  <strong>Tiện ích thanh Menu Bar gọn nhẹ cho macOS</strong><br>
  Tai thỏ Dynamic Island · Bộ trộn âm thanh từng ứng dụng · Theo dõi phần cứng & Quạt tản nhiệt
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-blue?style=flat-square" alt="Apple Silicon & Intel">
  <img src="https://img.shields.io/badge/Language-Swift%20%7C%20SwiftUI-orange?style=flat-square&logo=swift" alt="Swift & SwiftUI">
  <img src="https://img.shields.io/badge/License-GPL--3.0-green?style=flat-square" alt="License">
</p>

---

## Giới thiệu

**SenseBar** là tiện ích hệ thống gọn nhẹ dành cho macOS, tập trung vào 3 tính năng thiết thực nhất:
1. **Tai thỏ & Dynamic Island**: Biến phần tai thỏ MacBook thành khu vực điều khiển nhanh với trình phát nhạc, sóng nhạc, thông báo hệ thống và lăn chuột chỉnh âm lượng/độ sáng.
2. **Bộ trộn âm thanh (Audio Studio)**: Điều chỉnh âm lượng riêng cho từng ứng dụng (0% – 200%), chuyển đổi nhanh thiết bị loa/micro và tự động tắt tiếng khi rút tai nghe.
3. **Theo dõi phần cứng & Quạt tản nhiệt**: Xem trực tiếp nhiệt độ CPU/GPU, mức dùng RAM, tốc độ mạng, pin và chủ động điều khiển tốc độ quạt trên máy Mac.

---

## Các tính năng chính

### 1. Tai thỏ & Dynamic Island
* **Trình phát nhạc (Now Playing)**: Hiển thị bài hát đang phát, ảnh bìa album và các nút điều khiển chuyển bài ngay trên vùng tai thỏ.
* **Sóng nhạc (Audio Visualizer)**: Hiệu ứng sóng âm chuyển động mượt mà theo nhạc đang phát.
* **Cuộn chuột chỉnh nhanh**: Đưa chuột lên vùng tai thỏ và lăn chuột để tăng/giảm nhanh âm lượng hoặc độ sáng màn hình.
* **Thông báo hệ thống**: Hiển thị gọn gàng các thông báo và trạng thái hệ thống ngay trên Dynamic Island.

### 2. Bộ trộn âm thanh (Audio Studio)
* **Âm lượng từng ứng dụng**: Điều chỉnh âm lượng độc lập cho từng ứng dụng đang chạy (Safari, Chrome, Spotify, Discord...) mà không cần cài đặt driver ngoài.
* **Khuếch đại âm lượng đến 200%**: Tăng âm lượng vượt mức tối đa mặc định cho các video hoặc cuộc gọi có âm thanh nhỏ.
* **Đổi nhanh Loa / Micro & Tắt nhanh Micro**: Chuyển đổi tức thì thiết bị đầu ra/đầu vào âm thanh và ngắt nhanh micro toàn hệ thống.
* **An toàn tai nghe**: Tự động ngắt âm lượng loa ngoài khi tai nghe bị rút đột ngột.

### 3. Theo dõi phần cứng & Quạt tản nhiệt
* **Thông số thời gian thực**: Theo dõi nhiệt độ CPU/GPU, mức dùng bộ nhớ RAM, tốc độ mạng (Upload/Download) và tình trạng Pin.
* **Điều khiển tốc độ quạt (SMC)**: Tự động hoặc chủ động điều chỉnh tốc độ quạt tản nhiệt trên máy Mac.

---

## Công nghệ sử dụng

* **Giao diện**: 100% Native Swift & SwiftUI kết hợp AppKit (`NSStatusItem`, `NSPanel`, `NSWindow`).
* **Âm thanh**: `CoreAudio`, `AudioToolbox` & `ScreenCaptureKit`.
* **Phần cứng & Cảm biến**: `IOKit` & `SMC` (System Management Controller).

---

## Hướng dẫn Build & Chạy thử

Yêu cầu hệ thống: **macOS 14.0 (Sonoma)** trở lên và **Xcode Command Line Tools**.

```bash
# 1. Clone dự án
git clone https://github.com/Ngochiendev/SenseBar.git
cd SenseBar

# 2. Biên dịch và đóng gói SenseBar.app
./build-app.sh

# 3. Mở ứng dụng
open build/SenseBar.app
```

---

## Giấy phép

Dự án được phân phối dưới giấy phép **GNU General Public License v3.0 (GPL-3.0)** — xem chi tiết tại file [LICENSE](LICENSE).
