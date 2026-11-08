import AppKit
import SwiftUI

// MARK: - NotchTranslucentMaterial (macOS 14 - 15 blur backdrop)

public struct NotchTranslucentMaterial: NSViewRepresentable {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
    }
}

// MARK: - View Extension cho Liquid Glass & Material Cao Cấp

public extension View {
    /// Áp dụng giao diện Liquid Glass chuẩn macOS 26+ hoặc kính mờ xuyên thấu trên macOS 14 - 15
    @ViewBuilder
    func senseLiquidGlass(cornerRadius: CGFloat = 16, enabled: Bool = true, isDark: Bool = true) -> some View {
        if enabled {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                self
                    .background(
                        Color.clear
                            .glassEffect(.regular, in: shape)
                            .overlay(
                                shape.fill(isDark ? Color.black.opacity(0.35) : Color.white.opacity(0.40))
                            )
                            .overlay(
                                shape.strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isDark ? 0.22 : 0.45),
                                            Color.white.opacity(0.06),
                                            Color.black.opacity(isDark ? 0.35 : 0.10)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                            )
                    )
            } else {
                classicGlass(cornerRadius: cornerRadius, isDark: isDark)
            }
            #else
            classicGlass(cornerRadius: cornerRadius, isDark: isDark)
            #endif
        } else {
            self
        }
    }

    @ViewBuilder
    private func classicGlass(cornerRadius: CGFloat, isDark: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self
            .background(
                ZStack {
                    NotchTranslucentMaterial(cornerRadius: cornerRadius)

                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    (isDark ? Color.black : Color.white).opacity(0.30),
                                    (isDark ? Color.black : Color.white).opacity(0.50)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.28 : 0.60),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(isDark ? 0.30 : 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
            )
    }
}

