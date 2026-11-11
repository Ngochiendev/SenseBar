import SwiftUI

/// Trạng thái pet trên đảo thật.
struct PetInteractionStage: View {
    let look: PetLook
    let side: PetSide
    @ObservedObject private var pet = PetService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let track = PetEngine.track(stripWidth: 148, stripHeight: 24, wing: 38,
                                            cameraWidth: 72, floats: false, bodyHeight: 24, side: side)
                ZStack(alignment: .top) {
                    LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.04)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Rectangle().fill(Color.black.opacity(0.22)).frame(height: 18)
                    NotchAttachedShape(topShoulder: 8, bottomRadius: 10)
                        .fill(.black).frame(width: 148, height: 24)
                        .overlay(alignment: .top) {
                            PetTrackView(look: look, track: track, rests: true,
                                         visit: pet.currentVisit, mood: pet.mood,
                                         reaction: pet.currentReaction, awake: pet.isEnabled)
                                .frame(width: track.width, height: track.height)
                        }
                    if let cue = pet.currentStatusCue {
                        Label(cue.title(using: l10n), systemImage: cue.symbol)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                            .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 6)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .frame(width: proxy.size.width, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .frame(height: 74)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 5)], alignment: .leading, spacing: 5) {
                chip("Chào", "Hello", symbol: "hand.wave.fill", color: .blue) { pet.triggerReaction(.wakeUp) }
                chip("Tải xong", "Downloaded", symbol: "arrow.down.circle.fill", color: .teal) { pet.triggerReaction(.celebrate) }
                chip("Pin yếu", "Low battery", symbol: "battery.25percent", color: .red) { pet.triggerReaction(.yawn) }
                chip("Sạc pin", "Charging", symbol: "bolt.fill", color: .yellow) { pet.chargingConnected() }
                chip("Tải lỗi", "Download error", symbol: "exclamationmark.arrow.triangle.2.circlepath", color: .orange) { pet.downloadFailed() }
                chip("Quẩy nhạc", "Dance", symbol: "music.note", color: .purple) { pet.triggerReaction(.groove) }
                chip("Thả tim", "Love", symbol: "heart.fill", color: .pink) { pet.triggerReaction(.love) }
            }
            Text(l10n.string(vi: "Nhấn để thử trên cả sân khấu và notch/capsule. Tự trở lại sau 4 giây.",
                             en: "Try on the stage and notch/capsule. Returns automatically after 4 seconds."))
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .animation(.easeInOut(duration: 0.18), value: pet.currentStatusCue?.id)
    }

    private func chip(_ vi: String, _ en: String, symbol: String, color: Color,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(l10n.string(vi: vi, en: en)).lineLimit(1)
            }
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
