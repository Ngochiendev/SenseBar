import Foundation

enum CrossPetCharacter: String, CaseIterable, Identifiable {
    case gpt, claude, deepseek, gemini, glm, qwen, grok
    var id: String { rawValue }
    var name: String {
        switch self {
        case .gpt: "GPT"
        case .claude: "Claude"
        case .deepseek: "DeepSeek"
        case .gemini: "Gemini"
        case .glm: "GLM"
        case .qwen: "Qwen"
        case .grok: "Grok"
        }
    }
    var style: PetStyle {
        switch self {
        case .gpt: .crossGPT
        case .claude: .crossClaude
        case .deepseek: .crossDeepSeek
        case .gemini: .crossGemini
        case .glm: .crossGLM
        case .qwen: .crossQwen
        case .grok: .crossGrok
        }
    }
    /// Sự kiện tạm thời ưu tiên hơn nhạc; kết thúc sự kiện sẽ tự trở về tư thế nghe nhạc.
    static func presentationReaction(event: PetReaction?, mediaPlaying: Bool) -> PetReaction? {
        event ?? (mediaPlaying ? .groove : nil)
    }

    var hasBlink: Bool { self != .gemini }
    var bundledPoses: [String] {
        let stems = ["avatar", "idle", "roll_call", "happy", "sleeping", "pat", "thinking", "searching",
                     "oops", "surprised", "tired", "hum", "listening", "reading"]
        return stems.map(assetName) + (hasBlink ? ["idle-blink"] : [])
    }

    private func assetName(_ stem: String) -> String {
        self == .claude && ["happy", "sleeping", "pat", "reading"].contains(stem) ? stem + "-2" : stem
    }

    func pose(mood: PetMood, reaction: PetReaction?, compact: Bool = false) -> String {
        if reaction == .wakeUp || (compact && mood == .idle && reaction == nil) { return "roll_call" }
        switch mood {
        case .thinking: return "thinking"
        case .searching: return "searching"
        case .determined: return assetName("reading")
        case .exhausted: return "tired"
        default: break
        }
        let stem: String
        switch reaction {
        case .love: stem = "pat"
        case .yawn: stem = "tired"
        case .groove: stem = "hum"
        case .confused: stem = "oops"
        case .surprised, .flash, .perk: stem = "surprised"
        case .hush: stem = "listening"
        case .ready: stem = "reading"
        case .celebrate, .bounce: stem = "happy"
        default:
            switch mood {
            case .sleeping, .sleepy: stem = "sleeping"
            case .love: stem = "pat"
            case .happy, .wink, .charging: stem = "happy"
            case .downloadError, .confused: stem = "oops"
            case .surprised: stem = "surprised"
            case .muted, .alert: stem = "listening"
            default: stem = "idle"
            }
        }
        return assetName(stem)
    }
}

extension PetStyle {
    var crossPet: CrossPetCharacter? {
        CrossPetCharacter.allCases.first { $0.style == self }
    }
}

/// Khung ảnh thu gọn bám đáy; kích thước thật theo tỉ lệ ảnh, không dùng ô vuông letterbox.
enum CrossPetLayout {
    static func compactFrame(image: CGSize, track: PetTrack, rests: Bool) -> CGRect {
        guard image.width > 0, image.height > 0, track.width > 0, track.height > 0 else { return .zero }
        let topInset = max(0, track.ceiling)
        let left: CGFloat
        let right: CGFloat
        if let camera = track.hidden {
            if track.rest < camera.lowerBound {
                left = min(12, camera.lowerBound)
                right = max(left, camera.lowerBound - 1)
            } else {
                left = min(track.width, camera.upperBound + 1)
                right = max(left, track.width - 12)
            }
        } else {
            let radius = min(track.height / 2, track.width / 2)
            let cornerInset = radius + 0.5
            left = min(cornerInset, track.width / 2)
            right = max(left, track.width - left)
        }
        let availableHeight = max(0, track.height - topInset)
        let factor = min(availableHeight / image.height, max(0, right - left) / image.width)
        let size = CGSize(width: image.width * factor, height: image.height * factor)
        let restingCenter = min(right - size.width / 2, max(left + size.width / 2, track.rest))
        // Dịch từ vị trí đã căn mép để offset không bị phép clamp triệt tiêu.
        let horizontalOffset: CGFloat
        if let camera = track.hidden {
            // Hai cánh notch dịch về phía giữa, tránh vùng camera thật.
            horizontalOffset = (track.rest < camera.lowerBound ? 16 : -16) * track.scale
        } else {
            horizontalOffset = -10 * track.scale
        }
        let minimumCenter = max(0, left + min(0, horizontalOffset)) + size.width / 2
        let maximumCenter = right - size.width / 2
        let center = min(maximumCenter, max(minimumCenter, restingCenter + horizontalOffset))
        return CGRect(x: rests ? center - size.width / 2 : -size.width,
                      y: track.height - size.height,
                      width: size.width, height: size.height)
    }
}
