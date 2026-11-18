import AppKit
import SwiftUI

/// Thẻ chọn kiểu Capsule / Notch cho màn hình không có tai thỏ.
struct IslandStyleCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var islandController = IslandController.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"
    @AppStorage(DefaultsKey.notchDeviceNotices) private var deviceNotices = true
    @AppStorage(DefaultsKey.notchLowPeripheralBattery) private var lowBattery = true
    @AppStorage(DefaultsKey.peripheralBatteryThreshold) private var batteryThreshold = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(vi: "Màn hình không có tai thỏ", en: "Displays without a notch"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                styleSilhouetteButton(id: "pill", title: l10n.string(vi: "Capsule", en: "Capsule"))
                styleSilhouetteButton(id: "notch", title: l10n.string(vi: "Notch", en: "Notch"))
            }

            if islandController.hasNotchedDisplay {
                notchedDisplayNote
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(l10n.string(vi: "Thông báo phụ kiện", en: "Accessory alerts"), systemImage: "airpodspro")
                    .font(.system(size: 11, weight: .bold))
                DeviceAlertsIllustration(enabled: deviceNotices)
                    .frame(height: 68)
            }
            .padding(.top, 2)
            VStack(spacing: 0) {
                noticeToggle(
                    l10n.string(vi: "Thông báo sạc & kết nối thiết bị", en: "Power & device connection alerts"),
                    detail: l10n.string(
                        vi: "Nhận diện phụ kiện khi bạn cấp quyền Bluetooth.",
                        en: "Identify accessories after you allow Bluetooth access."
                    ),
                    isOn: deviceNoticesBinding
                )
                Divider().opacity(0.35)
                noticeToggle(
                    l10n.string(vi: "Cảnh báo pin phụ kiện", en: "Accessory low battery"),
                    isOn: $lowBattery
                )
                    .disabled(!deviceNotices)
                    .opacity(deviceNotices ? 1 : 0.48)
                if deviceNotices && lowBattery {
                    Divider().opacity(0.35)
                    HStack {
                        Text(l10n.string(vi: "Nhắc khi pin còn", en: "Alert at"))
                            .font(.system(size: 11))
                        Spacer()
                        Picker(l10n.string(vi: "Ngưỡng pin yếu", en: "Low battery threshold"), selection: $batteryThreshold) {
                            ForEach(Array(stride(from: 5, through: 50, by: 5)), id: \.self) { level in
                                Text("\(level)%").tag(level)
                            }
                        }
                        .labelsHidden().frame(width: 76).controlSize(.small)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 10)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            if deviceNotices && !permissions.bluetoothGranted {
                Button {
                    permissions.requestBluetooth()
                } label: {
                    Label(l10n.string(vi: "Cho phép Bluetooth để nhận diện phụ kiện", en: "Allow Bluetooth to identify accessories"), systemImage: "hand.raised")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            HStack {
                Spacer()
                Menu {
                    ForEach(DeviceNoticeService.Preview.allCases, id: \.self) { preview in
                        Button(preview.title) { DeviceNoticeService.shared.preview(preview) }
                    }
                } label: {
                    Label(l10n.string(vi: "Xem thử thông báo", en: "Preview alerts"), systemImage: "play.circle")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!deviceNotices)
            }
        }
        .panelCard()
    }

    private var deviceNoticesBinding: Binding<Bool> {
        Binding(get: { deviceNotices }, set: { enabled in
            deviceNotices = enabled
            if !enabled { lowBattery = false }
        })
    }

    private func noticeToggle(_ title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                if let detail {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    /// Lưu ý: màn hình có tai thỏ thật luôn dùng Notch, lựa chọn trên chỉ áp dụng cho màn hình rời.
    private var notchedDisplayNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(.blue)
            Text(l10n.string(
                vi: "Màn hình MacBook có tai thỏ luôn dùng kiểu Notch để ôm sát camera. Lựa chọn trên chỉ áp dụng cho màn hình không có tai thỏ.",
                en: "Notched MacBook displays always use the Notch style to fit the camera. This choice applies only to displays without a notch."
            ))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.blue.opacity(0.07))
        )
    }

    private func styleSilhouetteButton(id: String, title: String) -> some View {
        let isSelected = notchStyle == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                notchStyle = id
            }
            islandController.syncVisibility()
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isSelected
                                    ? [Color.blue.opacity(0.20), Color.blue.opacity(0.06)]
                                    : [Color.primary.opacity(0.06), Color.primary.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 46)

                    HStack(spacing: 3) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 5.5))
                            .opacity(0.6)
                        Spacer()
                        Circle().fill(Color.primary.opacity(0.35)).frame(width: 2.5, height: 2.5)
                        Circle().fill(Color.primary.opacity(0.35)).frame(width: 2.5, height: 2.5)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 12)
                    .background(Rectangle().fill(Color.primary.opacity(0.06)))

                    if id == "pill" {
                        Capsule(style: .continuous)
                            .fill(isSelected ? Color.blue : Color.primary.opacity(0.75))
                            .frame(width: 40, height: 7.5)
                            .padding(.top, 2.2)
                            .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.2), radius: 2, y: 1)
                    } else {
                        NotchAttachedShape(topShoulder: 2.5, bottomRadius: 3.5)
                            .fill(isSelected ? Color.blue : Color.primary.opacity(0.75))
                            .frame(width: 42, height: 12)
                            .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.2), radius: 2, y: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                HStack(spacing: 4) {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.35))
                        .frame(width: 5.5, height: 5.5)
                    Text(title)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.blue : Color.primary.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }
}
