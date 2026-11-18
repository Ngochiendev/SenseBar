## Tóm tắt / Summary

<!-- Mô tả ngắn gọn vấn đề cần giải quyết và hành vi sau khi thay đổi / Briefly describe the problem and the resulting behavior -->

Related Issue: <!-- Ví dụ: Closes #123 (nếu có) -->

## Phạm vi ảnh hưởng / Affected Subsystem

- [ ] `App` (Lifecycle / Menu Bar)
- [ ] `Core` (AudioTapEngine / Permissions / ScreenGeometry / PetEngine)
- [ ] `Services` (AudioStudio / Music / Device / Update)
- [ ] `Views` (Dynamic Island / Popover / Settings / Onboarding)
- [ ] `Bridges` (`SenseBarAudioBridge` / `NowPlayingBridge`)
- [ ] `Tools` / Build / Docs / CI

## Kiểm tra tự động & thủ công / Validation

### Tự động / Automated
- [ ] `swift build` thành công không phát sinh cảnh báo Swift 6 concurrency mới
- [ ] `.build/debug/SenseBar --selftest` (hoặc `./build/SenseBar.app/Contents/MacOS/SenseBar --selftest`) đạt `SELFTEST OK`
- [ ] `git diff --check` sạch sẽ

### Thủ công / Manual Testing
- **Phiên bản macOS / macOS version:** <!-- Ví dụ: macOS 15.3 / macOS 26.2 -->
- **Loại màn hình / Display config:** <!-- Ví dụ: MacBook Notch / External Capsule -->
- **Thiết bị âm thanh & phụ kiện / Audio & accessories:** <!-- Nếu liên quan -->
- **Kết quả kiểm tra / Result:** <!-- Mô tả ngắn kết quả thực tế -->

## Ảnh chụp / Video (Nếu thay đổi UI / For UI Changes)

<!-- Đính kèm ảnh chụp màn hình hoặc GIF trước/sau -->

## Lưu ý về Quyền, Dữ liệu & Hiệu năng / Permissions, Privacy & Performance

- [ ] Không tự ý thêm quyền hệ thống, network request hoặc telemetry ngoài phạm vi đã thảo luận
- [ ] Không cấp phát bộ nhớ, lock hoặc log trong CoreAudio realtime callback
- [ ] Text giao diện mới (nếu có) đã được bổ sung đầy đủ cả Tiếng Việt và Tiếng Anh trong `L10n.swift`
