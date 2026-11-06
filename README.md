# SenseBar

<p align="center">
  <strong>The Sensory Companion for macOS</strong><br>
  Dynamic Notch · Intelligent Audio Mixer · Native Hardware Telemetry
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-blue?style=flat-square" alt="Apple Silicon & Intel">
  <img src="https://img.shields.io/badge/Language-Swift%20%7C%20SwiftUI-orange?style=flat-square&logo=swift" alt="Swift & SwiftUI">
  <img src="https://img.shields.io/badge/License-GPL--3.0-green?style=flat-square" alt="License">
</p>

---

## 🌟 Overview

**SenseBar** là bộ tiện ích hệ thống thế hệ mới dành riêng cho macOS, kết hợp hoàn hảo giữa:
1. **Dynamic Island / Notch HUD**: Biến tai thỏ MacBook thành trung tâm điều khiển sống động.
2. **Audio & Meeting Center**: Quản lý âm thanh từng app, chống ồn, tự hạ nhạc khi họp và ngắt kết nối an toàn.
3. **Hardware & System Telemetry**: Giám sát nhiệt độ, tốc độ quạt và chống ngủ máy siêu nhẹ không tốn tài nguyên.

---

## 🎯 Core Features

### 1. 🏝️ Dynamic Island & Vùng Notch (Interactive HUD)
* **NowPlaying & Live Lyrics**: Hiển thị bài hát đang phát, album art và lời bài hát đồng bộ thời gian thực theo nhạc.
* **Mini Audio Visualizer**: Sóng âm động (sound wave bars) nhảy múa tinh tế hai bên tai thỏ khi phát âm thanh hoặc đàm thoại.
* **Quick Volume / Brightness Scrub on Notch**: Rê chuột lên vùng tai thỏ rồi cuộn con lăn (hoặc vuốt 2 ngón) để tăng/giảm nhanh âm lượng hoặc độ sáng.
* **Privacy Indicator Peek**: Khi có ứng dụng ngầm truy cập Mic/Camera/Vị trí, Notch tự mở rộng thông báo tên ứng dụng (*ví dụ: "Zoom đang dùng Micro"*).
* **Camera Mirror**: Xem trước khung hình webcam trực tiếp ngay tại Notch trước khi tham gia cuộc họp.
* **Download & Timer Progress**: Vòng tròn/thanh hiển thị tiến trình tải file và đếm ngược thời gian ôm sát mép tai thỏ.
* **Contextual Drop Notch**: Kéo thả file lên Notch để mở các thao tác thông minh (nén ảnh, đổi định dạng, tạo liên kết tạm).
* **Mac Live Activities**: Hiển thị trạng thái sự kiện thời gian thực (meeting sắp diễn ra, tiến trình render video, build task).

### 2. 🎧 Âm thanh & Cuộc họp (Intelligent Audio Hub)
* **Per-App Volume Mixer**: Điều chỉnh âm lượng độc lập cho từng ứng dụng (Chrome, Spotify, Zoom, Discord...) mà không cần driver kernel.
* **Volume Boost > 100%**: Kích âm lượng vượt ngưỡng tối đa của hệ thống cho các video hoặc cuộc gọi quá nhỏ.
* **Global Mic Mute & Indicator**: Phím tắt ngắt micro toàn hệ thống tức thì kèm đèn trạng thái cảnh báo rõ ràng.
* **Per-App Output Routing**: Điều hướng âm thanh từng app đến các thiết bị phát khác nhau (ví dụ: nhạc phát ra loa ngoài, cuộc họp vào tai nghe).
* **Music App Blocker**: Chặn macOS tự động mở Apple Music khi nhấn phím media hoặc cắm tai nghe Bluetooth.
* **Smart Auto-Ducking**: Tự động hạ âm lượng nhạc nền khi phát hiện tiếng người nói trong cuộc họp và tự tăng lại khi im lặng.
* **Local Meeting AI (Whisper Offline)**: Ghi âm cuộc họp 2 chiều và tự động tóm tắt nội dung ngay trên máy qua AI offline bảo mật tuyệt đối.
* **Headphone Disconnect Auto-Safety**: Tự động dừng nhạc và hạ âm lượng loa ngoài về 0% ngay khi tai nghe bị ngắt kết nối đột ngột.

### 3. ⚙️ Giám sát Phần cứng & Trạng thái Hệ thống (Hardware & System)
* **System Status Bar**: Đưa thông số CPU, RAM, nhiệt độ chip, tốc độ mạng trực tiếp lên Menu Bar.
* **Fan Control**: Điều chỉnh tốc độ quạt thủ công hoặc theo biểu đồ nhiệt độ chip Apple Silicon.
* **Keep Awake (Caffeine)**: Chống ngủ màn hình/hệ thống theo hẹn giờ hoặc khi có tác vụ dài đang chạy ngầm.

---
  
## 🛠️ Tech Stack & Architecture

* **UI Layer**: 100% Swift & SwiftUI kết hợp AppKit (`NSPanel`, `NSWindow.Level.statusBar`).
* **Audio Engine**: `CoreAudio`, `AudioToolbox` & `ScreenCaptureKit` (cho per-app audio stream capture không cần kext).
* **Hardware & Sensor**: `IOKit`, `SMCKit` (System Management Controller) để đọc nhiệt độ và điều khiển quạt.
* **On-Device AI**: `Whisper.cpp` / CoreML Metal tăng tốc phần cứng cho tính năng tóm tắt cuộc họp offline.

---

## 🚀 Getting Started