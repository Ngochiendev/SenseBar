import SwiftUI

/// Dùng cùng sân khấu tương tác với phần cài đặt thú cưng trong popover.
struct PetOnboardingIllustration: View {
    let enabled: Bool
    var look: PetLook = .standard
    @AppStorage(DefaultsKey.petSide) private var side = "left"

    var body: some View {
        PetInteractionStage(look: look, side: PetSide(rawValue: side) ?? .left, showsFullBody: false)
            .disabled(!enabled)
            .allowsHitTesting(enabled)
            .opacity(enabled ? 1 : 0.5)
    }
}
