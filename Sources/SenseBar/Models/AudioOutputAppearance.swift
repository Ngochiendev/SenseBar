import CoreAudio

enum AudioOutputKind: CaseIterable, Equatable, Sendable {
    case macBook, builtIn, airPods, airPodsPro, airPodsMax, headphones
    case display, usb, bluetooth, airPlay, virtual, aggregate, speaker

    var symbol: String {
        switch self {
        case .macBook: "laptopcomputer"
        case .builtIn: "desktopcomputer"
        case .airPods: "airpods"
        case .airPodsPro: "airpodspro"
        case .airPodsMax: "airpodsmax"
        case .headphones: "headphones"
        case .display: "display"
        case .usb: "cable.connector"
        case .bluetooth: "wave.3.right.circle.fill"
        case .airPlay: "airplay.audio"
        case .virtual: "waveform.path"
        case .aggregate: "square.stack.3d.up.fill"
        case .speaker: "hifispeaker.fill"
        }
    }

    /// HAL transport/terminal takes precedence; model names only refine otherwise unknown types.
    static func classify(name: String, transport: UInt32, terminal: UInt32) -> Self {
        switch transport {
        case kAudioDeviceTransportTypeVirtual: return .virtual
        case kAudioDeviceTransportTypeAggregate: return .aggregate
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        default: break
        }
        let name = name.lowercased()
        if name.contains("airpods max") { return .airPodsMax }
        if name.contains("airpods pro") { return .airPodsPro }
        if name.contains("airpods") { return .airPods }
        if terminal == kAudioStreamTerminalTypeHeadphones || name.contains("headphone")
            || name.contains("headset") || name.contains("tai nghe") { return .headphones }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return name.contains("macbook") ? .macBook : .builtIn
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        default:
            if name.contains("macbook") { return .macBook }
            if name.contains("built-in") { return .builtIn }
            return .speaker
        }
    }
}
