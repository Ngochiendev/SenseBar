# Security Policy

<p align="center">
  <strong>Help keep SenseBar and its users safe.</strong><br>
  <strong>Giúp SenseBar và người dùng luôn an toàn.</strong>
</p>

<p align="center"><a href="#tiếng-việt">Tiếng Việt</a> · <a href="#english">English</a></p>

---

## Tiếng Việt

### Báo cáo riêng tư

Nếu bạn phát hiện lỗ hổng, vui lòng **không đăng chi tiết trong Issue, Discussion hoặc pull request công khai**.

Gửi báo cáo qua [GitHub Private Vulnerability Reporting](https://github.com/Ngochiendev/SenseBar/security/advisories/new). Nếu kênh này chưa khả dụng, hãy mở một issue ngắn yêu cầu maintainer cung cấp kênh liên hệ riêng và không kèm chi tiết kỹ thuật.

Báo cáo nên gồm:

- Phiên bản SenseBar, macOS và kiến trúc máy.
- Tác động thực tế và điều kiện để lỗi xảy ra.
- Các bước tái hiện tối thiểu hoặc proof of concept an toàn.
- Component bị ảnh hưởng, log hoặc crash report đã xóa dữ liệu cá nhân.
- Đề xuất bản vá nếu có.
- Tên bạn muốn được ghi nhận, hoặc yêu cầu ẩn danh.

Không gửi password, Apple ID, certificate, private key, provisioning profile, địa chỉ Bluetooth đầy đủ hoặc dữ liệu âm thanh của người khác.

### Phạm vi được xem là bảo mật

Hãy báo cáo riêng các vấn đề có thể:

- Vượt qua, lạm dụng hoặc kích hoạt quyền Trợ năng, Bluetooth, Audio Capture hay Automation ngoài ý muốn.
- Đọc, lưu hoặc truyền dữ liệu Now Playing, âm thanh hay thiết bị trái với mô tả.
- Thực thi lệnh, nạp thư viện hoặc mở URL từ dữ liệu không tin cậy.
- Chiếm quyền điều khiển hoặc giả mạo onboarding, Menu Bar hay Dynamic Island.
- Gây lỗi bộ nhớ trong CoreAudio callback, bridge C/Objective-C hoặc parser dữ liệu thiết bị.
- Làm lộ secret CI/CD, certificate, thông tin ký hoặc notarization.
- Thay thế binary, can thiệp cập nhật hoặc bỏ qua xác minh artifact.
- Gây crash hoặc treo app thông qua dữ liệu do ứng dụng hay thiết bị khác kiểm soát.

Lỗi giao diện thông thường, lỗi tương thích thiết bị và yêu cầu tính năng có thể gửi qua [GitHub Issues](https://github.com/Ngochiendev/SenseBar/issues).

### Phiên bản hỗ trợ

Bản phát hành mới nhất và nhánh `main` được ưu tiên nhận bản vá. Phiên bản cũ được xem xét tùy mức độ và khả năng backport. Fork và build đã sửa đổi không thuộc phạm vi hỗ trợ chính thức.

Nếu có thể, hãy xác nhận lỗi trên bản phát hành mới nhất hoặc commit mới nhất của nhánh `dev`.

### Điều gì xảy ra sau khi báo cáo?

Dự án đặt mục tiêu xác nhận báo cáo trong vòng 7 ngày, sau đó đánh giá tác động và phối hợp riêng để chuẩn bị bản vá. Thời gian phát hành phụ thuộc vào độ phức tạp, khả năng tái hiện và quy trình ký/notarize.

Vui lòng giữ kín chi tiết cho đến khi bản vá được phát hành và người dùng đã có thời gian hợp lý để cập nhật. Người báo cáo sẽ được ghi nhận nếu mong muốn.

### Ranh giới dữ liệu

- SenseBar xử lý âm thanh và dữ liệu thiết bị trên máy. Khi Zen Browser thiếu ảnh bìa, SenseBar đọc tiêu đề và URL của các tab trong tệp khôi phục phiên trên máy. Nếu tìm thấy video phù hợp, ứng dụng gửi ID video đến YouTube để tải ảnh thu nhỏ. Nếu phát hiện YouTube Music nhưng chưa tìm được ID video, ứng dụng có thể gửi tên bài và nghệ sĩ đến dịch vụ tìm kiếm iTunes của Apple để lấy ảnh bìa.
- SenseBar không có account, quảng cáo hoặc telemetry riêng.
- Kiểm tra cập nhật sử dụng Sparkle qua HTTPS tới appcast đã ký (`updates.sensebar.site`) và có thể kiểm tra thủ công hoặc tắt tự động kiểm tra trong Cài đặt.
- Bluetooth chỉ bắt đầu sau khi người dùng bật thông báo thiết bị.
- Audio process tap chỉ được tạo khi Audio Studio cần điều chỉnh app.
- Trợ năng là quyền bắt buộc để hoàn tất onboarding và kích hoạt SenseBar.

Các thay đổi ảnh hưởng đến những ranh giới này phải được ghi rõ trong pull request và tài liệu phát hành.

---

## English

### Report privately

If you discover a vulnerability, **do not disclose technical details in a public Issue, Discussion, or pull request**.

Use [GitHub Private Vulnerability Reporting](https://github.com/Ngochiendev/SenseBar/security/advisories/new). If that channel is unavailable, open a short issue asking the maintainer for a private contact method and omit technical details.

Please include:

- SenseBar version, macOS version, and hardware architecture.
- Practical impact and conditions required to trigger the issue.
- Minimal reproduction steps or a safe proof of concept.
- Affected component and sanitized logs or crash reports.
- A proposed fix, if available.
- Your preferred credit, or a request to remain anonymous.

Do not send passwords, Apple IDs, certificates, private keys, provisioning profiles, complete Bluetooth addresses, or audio belonging to another person.

### Security scope

Please report issues privately when they could:

- Bypass, abuse, or unexpectedly trigger Accessibility, Bluetooth, Audio Capture, or Automation access.
- Read, store, or transmit Now Playing, audio, or device data contrary to the documentation.
- Execute commands, load libraries, or open URLs from untrusted input.
- Control or spoof onboarding, menu bar, or Dynamic Island surfaces.
- Cause memory-safety defects in CoreAudio callbacks, C/Objective-C bridges, or device parsers.
- Expose CI/CD secrets, certificates, signing, or notarization credentials.
- Replace binaries, tamper with updates, or bypass artifact verification.
- Crash or hang SenseBar through data controlled by another app or device.

Ordinary UI defects, device compatibility bugs, and feature requests belong in [GitHub Issues](https://github.com/Ngochiendev/SenseBar/issues).

### Supported versions

The latest release and `main` branch receive priority security fixes. Older versions are considered case by case when a safe backport is practical. Modified builds and third-party forks are outside official support.

When possible, confirm the issue on the latest release or latest `dev` commit.

### What happens after a report?

The project aims to acknowledge reports within 7 days, assess impact, and coordinate privately while preparing a fix. Release timing depends on complexity, reproducibility, and Apple signing/notarization requirements.

Please keep details private until a fix is available and users have had reasonable time to update. Reporters are credited when requested.

### Data boundaries

- SenseBar processes audio and device data locally. When artwork is missing in Zen Browser, SenseBar reads tab titles and URLs from local session recovery files. If it finds a matching video, it sends the video ID to YouTube to fetch a thumbnail. If it detects YouTube Music but cannot find a matching video ID, it may send the track title and artist to Apple’s iTunes Search service to fetch cover art.
- SenseBar has no account system, advertising, or first-party telemetry.
- Update checks use Sparkle over HTTPS against a signed appcast (`updates.sensebar.site`) and can be run manually or disabled in Settings.
- Bluetooth starts only after device notices are enabled.
- Audio process taps are created only when Audio Studio adjusts an app.
- Accessibility is required before onboarding can finish and SenseBar can activate.

Changes to these boundaries must be documented in the pull request and release materials.

---

This project is distributed under [GPL-3.0](LICENSE). For development and review requirements, see [CONTRIBUTING.md](CONTRIBUTING.md).
