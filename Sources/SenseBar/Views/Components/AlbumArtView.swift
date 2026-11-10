import AppKit
import SwiftUI

/// Ảnh bìa bài hát dùng chung cho Island và bản xem trước trong menu.
/// Khi chưa có ảnh bìa sẽ hiện nền gradient kèm biểu tượng nốt nhạc.
struct AlbumArtView: View {
    let artwork: NSImage?
    let size: CGFloat
    var isCircle: Bool = false
    var cornerRadius: CGFloat = 4.5

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isCircle ? size / 2 : cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(isCircle ? 0.18 : 0.16), lineWidth: 0.6))
    }

    @ViewBuilder
    private var content: some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.30, green: 0.42, blue: 0.95),
                    Color(red: 0.62, green: 0.28, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(.white)
            )
        }
    }
}
