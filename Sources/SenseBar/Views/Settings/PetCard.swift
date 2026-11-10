import SwiftUI

/// Thẻ cài đặt và tương tác thú cưng
public struct PetCard: View {
    @ObservedObject private var l10n = L10n.shared

    @AppStorage(DefaultsKey.petEnabled) private var enabled = true
    @AppStorage(DefaultsKey.petStyle) private var style = "minimal"
    @AppStorage(DefaultsKey.petShape) private var shape = "ball"
    @AppStorage(DefaultsKey.petPalette) private var palette = "pearl"
    @AppStorage(DefaultsKey.petSide) private var side = "left"
    @AppStorage(DefaultsKey.petVisits) private var visits = true

    // Danh sách hình dáng được giữ lại (đã loại bỏ egg và pill theo yêu cầu)
    private let allowedShapes: [PetShape] = [.ball, .squircle]

    public init() {}

    private var currentLook: PetLook {
        let validShape: PetShape = (shape == "squircle") ? .squircle : .ball
        return PetLook(
            style: PetStyle(rawValue: style) ?? .minimal,
            shape: validShape,
            palette: PetPalette(rawValue: palette) ?? .pearl
        )
    }

    private var currentSide: PetSide {
        PetSide(rawValue: side) ?? .left
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow

            if enabled {
                VStack(alignment: .leading, spacing: 12) {
                    PetInteractionStage(look: currentLook, side: currentSide)

                    Text(l10n.string(vi: "Tự ngủ sau 5 phút không thao tác · Chào khi mở máy · Phản ứng khi cắm sạc.", en: "Sleeps after 5 minutes idle · Greets on wake · Reacts to charging."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)


                    // Ngoại hình (Appearance)
                    appearanceControls

                    Divider().opacity(0.4)

                    // Vị trí & Hành vi (Behavior)
                    behaviorControls
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .panelCard()
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: enabled)
        .animation(.spring(response: 0.25, dampingFraction: 0.84), value: style)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.pink)
                .frame(width: 24, height: 24)
                .background(Color.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.string(vi: "Thú cưng (Companion)", en: "Companion"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                Text(l10n.string(
                    vi: "Bạn nhỏ sống trên Tai thỏ & Đảo động",
                    en: "A little friend on your Dynamic Island"
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
    }

    // MARK: - Appearance Controls

    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l10n.string(vi: "Ngoại hình", en: "Appearance"), systemImage: "paintpalette.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Kiểu: Tối giản vs Robot
            HStack(spacing: 8) {
                styleButton(
                    id: "minimal",
                    title: l10n.string(vi: "Tối giản", en: "Minimal"),
                    styleItem: .minimal
                )
                styleButton(
                    id: "robot",
                    title: "Robot",
                    styleItem: .robot
                )
            }

            // Hình dáng (chỉ hiện khi không phải Robot: Hình tròn vs Vuông bo)
            if currentLook.style != .robot {
                HStack(spacing: 8) {
                    Text(l10n.string(vi: "Hình dạng:", en: "Shape:"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(allowedShapes) { item in
                            let isSelected = currentLook.shape == item
                            Button {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    shape = item.rawValue
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    PetView(
                                        look: PetLook(style: .minimal, shape: item, palette: currentLook.palette),
                                        size: 15,
                                        idles: false
                                    )
                                    .frame(width: 15, height: 15)

                                    Text(item == .ball ? l10n.string(vi: "Hình tròn", en: "Ball") : l10n.string(vi: "Vuông bo", en: "Squircle"))
                                        .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            // Bảng màu 7 swatches
            HStack(spacing: 8) {
                Text(l10n.string(vi: "Màu sắc:", en: "Color:"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(PetPalette.allCases) { item in
                        let isSelected = currentLook.palette == item
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                palette = item.rawValue
                            }
                        } label: {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(cgColor: item.light.cgColor), Color(cgColor: item.shade.cgColor)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .frame(width: 17, height: 17)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                                .padding(2.5)
                                .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.8))
                        }
                        .buttonStyle(.plain)
                        .help(item.rawValue.capitalized)
                    }
                }
                Spacer()
            }
        }
    }

    private func styleButton(id: String, title: String, styleItem: PetStyle) -> some View {
        let isSelected = style == id
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                style = id
            }
        } label: {
            HStack(spacing: 6) {
                PetView(
                    look: PetLook(style: styleItem, shape: currentLook.shape, palette: currentLook.palette),
                    size: 20,
                    idles: false
                )
                .frame(width: 20, height: 20)
                .frame(width: 38, height: 24)
                .background(Color.black, in: Capsule())

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Behavior Controls

    private var behaviorControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l10n.string(vi: "Vị trí & Hoạt động", en: "Position & Behavior"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Chọn cánh trái / phải cạnh camera
            HStack(spacing: 8) {
                Text(l10n.string(vi: "Vị trí đậu:", en: "Resting side:"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    sideButton(target: .left, title: l10n.string(vi: "Cánh trái", en: "Left"))
                    sideButton(target: .right, title: l10n.string(vi: "Cánh phải", en: "Right"))
                }
                Spacer()
            }

            HStack {
                Label(l10n.string(vi: "Thỉnh thoảng đi dạo", en: "Stroll now and then"), systemImage: "figure.walk")
                    .font(.system(size: 10.5, weight: .medium))
                Spacer()
                Toggle("", isOn: $visits)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }

        }
    }

    private func sideButton(target: PetSide, title: String) -> some View {
        let isSelected = currentSide == target
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                side = target.rawValue
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: target == .left ? "arrow.left.to.line" : "arrow.right.to.line")
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }
}
