# Contributing to SenseBar / Đóng góp cho SenseBar

[Tiếng Việt](#tiếng-việt) · [English](#english)

Cảm ơn bạn đã quan tâm đến SenseBar. Thank you for helping improve SenseBar.

---

## Tiếng Việt

### Trước khi bắt đầu

SenseBar là ứng dụng macOS viết bằng Swift 6, SwiftUI và AppKit, đồng thời dùng CoreAudio, ApplicationServices, IOKit và các API hệ thống khác. Trước khi thay đổi mã nguồn:

1. Tìm trong [Issues](https://github.com/Ngochiendev/SenseBar/issues) để tránh trùng lặp.
2. Với thay đổi lớn về UX, kiến trúc, quyền hoặc API hệ thống, hãy mở issue mô tả vấn đề và phương án trước.
3. Với lỗi nhỏ, tài liệu hoặc bản vá rõ ràng, bạn có thể gửi pull request trực tiếp.
4. Lỗ hổng bảo mật phải được báo cáo theo [SECURITY.md](SECURITY.md), không đăng chi tiết công khai.

Bằng việc gửi đóng góp, bạn đồng ý phát hành phần đóng góp theo [GPL-3.0](LICENSE).

### Môi trường phát triển

Yêu cầu:

- macOS 14 Sonoma trở lên.
- Xcode Command Line Tools với Swift 6.
- Git và Zsh.
- Máy Apple Silicon hoặc Intel 64-bit.

Thiết lập:

```zsh
git clone https://github.com/Ngochiendev/SenseBar.git
cd SenseBar
git checkout dev
swift --version
```

Build nhanh:

```zsh
swift build
```

Build app debug và chạy:

```zsh
./build-app.sh --debug
killall SenseBar 2>/dev/null || true
open build/SenseBar.app
```

Build Universal hoặc DMG:

```zsh
./build-app.sh
./build-app.sh --dmg
```

Không cần certificate Developer ID để build cục bộ; script dùng chữ ký ad-hoc nếu không tìm thấy certificate. Notarization chỉ cần cho artifact phát hành.

### Cấu trúc mã nguồn

```text
Sources/SenseBar/App/       Vòng đời ứng dụng và Menu Bar
Sources/SenseBar/Core/      Hạ tầng cấp thấp, quyền và cấu hình
Sources/SenseBar/Services/  Nghiệp vụ và kết nối API hệ thống
Sources/SenseBar/Views/     SwiftUI/AppKit và giao diện
Sources/SenseBarAudioBridge/ Bridge C/Objective-C cho CoreAudio
Sources/NowPlayingBridge/   Bridge Now Playing
Resources/                  Info.plist, icon và tài nguyên
Tools/                      Build, icon, DMG và preview
```

Đặt code mới đúng tầng:

- Model dữ liệu thuần nằm gần service sử dụng nó hoặc trong `Models/` khi được dùng rộng.
- View và ViewModifier nằm trong `Views/`.
- Service kết nối hệ thống nằm trong `Services/`.
- Primitive cấp thấp, parser và bridge nằm trong `Core/` hoặc target bridge tương ứng.
- Khởi tạo và vòng đời nằm trong `App/`.

### Quy ước Swift

- Dùng Swift 6 và giữ code không có cảnh báo concurrency mới.
- `ObservableObject`, service điều khiển UI và ViewModel phải chạy trên `@MainActor`.
- Không block main thread bằng I/O, truy vấn CoreAudio, `system_profiler` hoặc công việc nặng.
- CoreAudio realtime callback không được cấp phát bộ nhớ, lock, log hoặc gọi API có thời gian không xác định.
- Dùng event/listener thay cho polling nhanh. Timer dự phòng phải có khoảng thời gian hợp lý và `tolerance`.
- Giải phóng observer, timer, audio tap, aggregate device và native handle khi dừng.
- Giữ dữ liệu quyền riêng tư trên máy; thêm network request hoặc telemetry cần được thảo luận và ghi tài liệu rõ.
- Ưu tiên API macOS công khai. Nếu dùng API private hoặc symbol động, cần fallback an toàn và mô tả rủi ro trong PR.
- Giữ UI hoạt động trên macOS 14–15; API Liquid Glass mới phải có availability check và fallback nhẹ.
- Viết comment giải thích lý do, invariant hoặc ràng buộc realtime; tránh comment lặp lại câu lệnh.

### UI và khả năng truy cập

- Kiểm tra giao diện sáng/tối, Reduce Motion, Reduce Transparency và Increase Contrast khi liên quan.
- Không dựa duy nhất vào màu sắc để biểu diễn trạng thái.
- Control có icon phải có accessibility label phù hợp.
- Giữ vùng bấm đủ lớn và căn tâm quang học cho toggle, radio và icon.
- Kiểm tra màn hình có tai thỏ, màn hình không tai thỏ và cấu hình nhiều màn hình khi thay đổi Island.
- Animation phải ngắn, có chủ đích và không tạo timer/render loop khi nội dung đứng yên.
- Text mới phải có cả tiếng Việt và tiếng Anh qua hệ thống `L10n` hiện có.

### Quyền và dữ liệu

Thay đổi liên quan quyền phải tuân theo nguyên tắc yêu cầu đúng lúc:

- Trợ năng là quyền bắt buộc trong onboarding.
- Bluetooth chỉ được kích hoạt sau khi người dùng bật thông báo phụ kiện.
- Audio Capture chỉ phát sinh khi mixer cần process tap.
- Mô tả quyền trong `Resources/Info.plist` phải nói đúng dữ liệu và mục đích sử dụng.
- Không thêm quyền, entitlement hoặc thu thập dữ liệu nếu tính năng không cần.
- Khi thu hồi quyền bắt buộc, app phải trở về trạng thái khóa an toàn.

Để test onboarding và quyền từ đầu:

```zsh
killall SenseBar 2>/dev/null || true
tccutil reset All com.sensebar.SenseBar
defaults delete com.sensebar.SenseBar 2>/dev/null || true
```

Lệnh cuối xóa toàn bộ cài đặt SenseBar cục bộ, vì vậy chỉ dùng trên môi trường test.

### Nhánh và quy trình pull request

1. Tạo nhánh từ `dev`:

   ```zsh
   git checkout dev
   git pull origin dev
   git checkout -b feat/short-description
   ```

2. Thực hiện một thay đổi có phạm vi rõ.
3. Rebase hoặc cập nhật với `dev` trước khi gửi.
4. Push nhánh và mở pull request vào `dev`.
5. `main` dành cho bản phát hành; không gửi feature PR trực tiếp vào `main` trừ khi maintainer yêu cầu.

Tên nhánh gợi ý:

- `feat/audio-output-switching`
- `fix/notch-hover-state`
- `perf/device-monitoring`
- `docs/security-policy`

### Commit

Dùng Conventional Commits và viết hoàn toàn bằng tiếng Anh:

```text
<type>(<scope>): <imperative subject>
```

Ví dụ:

```text
feat(audio): add output device switching
fix(permissions): keep onboarding locked until access is granted
perf(notch): stop animation work while island is idle
docs: add bilingual contributor guide
```

Các type thường dùng: `feat`, `fix`, `refactor`, `perf`, `style`, `test`, `docs`, `build`, `ci`, `chore`.

### Kiểm tra trước khi gửi PR

Chạy tối thiểu:

```zsh
swift build
.build/debug/SenseBar --selftest
git diff --check
```

Với thay đổi có ảnh hưởng đóng gói hoặc nhiều kiến trúc:

```zsh
./build-app.sh
./build/SenseBar.app/Contents/MacOS/SenseBar --selftest
lipo -info build/SenseBar.app/Contents/MacOS/SenseBar
lipo -info build/SenseBar.app/Contents/Frameworks/libSenseBarNowPlaying.dylib
```

Ngoài kiểm tra tự động, PR nên ghi rõ kiểm tra thủ công đã thực hiện: phiên bản macOS, loại màn hình, thiết bị âm thanh, trạng thái quyền và kết quả mong đợi.

Không cần thêm test chỉ để sao chép chi tiết implementation. Hãy thêm test cho parser, state transition, policy pin, tính toán hoặc bug có thể tái phát.

### Nội dung pull request

PR nên có:

- Vấn đề cụ thể và hành vi sau thay đổi.
- Phạm vi file hoặc subsystem bị ảnh hưởng.
- Cách kiểm tra tự động và thủ công.
- Ảnh/GIF cho thay đổi UI.
- Thay đổi về quyền, network, dữ liệu, CPU, GPU hoặc RAM.
- Rủi ro, giới hạn thiết bị/macOS và phương án fallback.
- Issue liên quan bằng `Closes #123` khi phù hợp.

Giữ PR tập trung. Không trộn refactor lớn, format toàn repository và tính năng mới nếu chúng không phụ thuộc nhau.

### Issue

Bug report nên có phiên bản SenseBar/macOS, kiến trúc máy, màn hình và thiết bị liên quan, bước tái hiện, hành vi mong đợi/thực tế, tần suất và log đã làm sạch. Feature request nên mô tả nhu cầu người dùng trước khi đề xuất giao diện hoặc implementation.

### Tài nguyên và mã bên thứ ba

- Không commit secret, certificate, file keychain, dữ liệu người dùng hoặc binary không rõ nguồn.
- Không sao chép mã từ dự án khác nếu giấy phép hoặc nguồn gốc không rõ.
- Khi tham khảo một implementation, hãy viết lại theo kiến trúc SenseBar và ghi attribution khi giấy phép yêu cầu.
- Asset mới phải có quyền sử dụng và tối ưu kích thước.
- Folder tham khảo cục bộ bị gitignore không được đưa vào pull request.

---

## English

### Before you start

SenseBar is a macOS application built with Swift 6, SwiftUI, AppKit, CoreAudio, ApplicationServices, IOKit, and related system frameworks.

1. Search [Issues](https://github.com/Ngochiendev/SenseBar/issues) before starting.
2. Open an issue first for substantial UX, architecture, permission, or system-API changes.
3. Small bug fixes, documentation changes, and well-scoped patches may go directly to a pull request.
4. Follow [SECURITY.md](SECURITY.md) for vulnerabilities and keep sensitive details private.

By contributing, you agree that your contribution is licensed under [GPL-3.0](LICENSE).

### Development environment

Requirements:

- macOS 14 Sonoma or later.
- Xcode Command Line Tools with Swift 6.
- Git and Zsh.
- Apple Silicon or 64-bit Intel hardware.

Setup and build:

```zsh
git clone https://github.com/Ngochiendev/SenseBar.git
cd SenseBar
git checkout dev
swift --version
swift build
```

Build and run the debug app:

```zsh
./build-app.sh --debug
killall SenseBar 2>/dev/null || true
open build/SenseBar.app
```

Universal and DMG builds:

```zsh
./build-app.sh
./build-app.sh --dmg
```

Local builds can use ad-hoc signing. Developer ID signing and notarization are needed only for release artifacts.

### Source layout

```text
Sources/SenseBar/App/       App lifecycle and menu bar
Sources/SenseBar/Core/      Low-level infrastructure, permissions, defaults
Sources/SenseBar/Services/  Domain logic and system API integration
Sources/SenseBar/Views/     SwiftUI/AppKit user interface
Sources/SenseBarAudioBridge/ C/Objective-C CoreAudio bridge
Sources/NowPlayingBridge/   Now Playing bridge
Resources/                  Info.plist, icons, and resources
Tools/                      Build, icon, DMG, and preview utilities
```

Place new code in the matching layer. UI belongs in `Views/`, system-facing services in `Services/`, low-level primitives and parsers in `Core/` or a bridge target, and lifecycle wiring in `App/`.

### Swift conventions

- Use Swift 6 and avoid introducing concurrency warnings.
- Run UI-facing `ObservableObject` types, services, and view models on `@MainActor`.
- Keep I/O, CoreAudio discovery, `system_profiler`, and heavy work off the main thread.
- Never allocate, lock, log, or call unbounded APIs from a real-time CoreAudio callback.
- Prefer system events and listeners over frequent polling. Give fallback timers a reasonable interval and `tolerance`.
- Release observers, timers, taps, aggregate devices, and native handles when stopping.
- Keep private data local. Discuss and document any network request or telemetry.
- Prefer public macOS APIs. Private or dynamically resolved APIs need a safe fallback and explicit PR risk notes.
- Keep macOS 14–15 working; gate newer Liquid Glass APIs and provide a lightweight fallback.
- Comment invariants, realtime constraints, and non-obvious decisions rather than restating code.

### UI and accessibility

- Test light/dark appearance and relevant accessibility settings.
- Do not communicate state through color alone.
- Add accessibility labels to icon-only controls.
- Keep practical hit areas and optical alignment.
- Test notched, non-notched, and multi-display layouts when changing Island UI.
- Keep animation bounded and stop render work for static content.
- Add Vietnamese and English text through the existing localization system.

### Permissions and data

Request access at the point of use:

- Accessibility is required during onboarding.
- Bluetooth starts after accessory notices are enabled.
- Audio Capture starts when the mixer needs a process tap.
- `Resources/Info.plist` descriptions must match actual behavior.
- Do not add entitlements, permission prompts, or data collection without a feature need.
- Revoking required access must return the app to a safe locked state.

Reset a test installation:

```zsh
killall SenseBar 2>/dev/null || true
tccutil reset All com.sensebar.SenseBar
defaults delete com.sensebar.SenseBar 2>/dev/null || true
```

The final command deletes all local SenseBar preferences. Use it only in a test environment.

### Branches and pull requests

1. Create a branch from `dev`.
2. Keep the change focused.
3. Update your branch from `dev` before submission.
4. Open the pull request against `dev`.
5. `main` is the release branch unless a maintainer requests otherwise.

```zsh
git checkout dev
git pull origin dev
git checkout -b feat/short-description
```

Suggested names include `feat/audio-output-switching`, `fix/notch-hover-state`, `perf/device-monitoring`, and `docs/security-policy`.

### Commits

Use English Conventional Commits:

```text
<type>(<scope>): <imperative subject>
```

Examples:

```text
feat(audio): add output device switching
fix(permissions): keep onboarding locked until access is granted
perf(notch): stop animation work while island is idle
docs: add bilingual contributor guide
```

Common types are `feat`, `fix`, `refactor`, `perf`, `style`, `test`, `docs`, `build`, `ci`, and `chore`.

### Validation

Run at minimum:

```zsh
swift build
.build/debug/SenseBar --selftest
git diff --check
```

For packaging or architecture-sensitive work:

```zsh
./build-app.sh
./build/SenseBar.app/Contents/MacOS/SenseBar --selftest
lipo -info build/SenseBar.app/Contents/MacOS/SenseBar
lipo -info build/SenseBar.app/Contents/Frameworks/libSenseBarNowPlaying.dylib
```

Document manual coverage in the PR: macOS version, display configuration, audio/accessory hardware, permission state, expected behavior, and result.

Add tests for parsers, state transitions, policies, calculations, and regressions. Avoid tests that merely duplicate implementation details.

### Pull request content

Include:

- The concrete problem and resulting behavior.
- Affected subsystem and scope.
- Automated and manual validation.
- Screenshots or GIFs for UI changes.
- Permission, network, privacy, CPU, GPU, or memory impact.
- Known device/macOS limits and fallback behavior.
- A linked issue such as `Closes #123` when applicable.

Keep pull requests focused. Avoid combining broad formatting, unrelated refactors, and new features.

### Issues and third-party material

Bug reports should include SenseBar/macOS versions, architecture, relevant displays and devices, reproduction steps, expected/actual behavior, frequency, and sanitized logs. Feature requests should explain the user need first.

Do not commit secrets, certificates, keychains, private user data, or material with unclear licensing. Reimplement referenced approaches for SenseBar's architecture and preserve attribution where a license requires it. New assets must have documented usage rights and reasonable file size. Local reference folders ignored by Git must remain outside pull requests.
