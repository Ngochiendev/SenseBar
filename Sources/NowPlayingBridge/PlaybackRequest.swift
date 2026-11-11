import Foundation

struct PlaybackRequest {
    let context: SessionTicket
    let command: Int32
    let position: Double?

    init?(_ line: String) {
        guard line.utf8.count <= 2_048,
              let data = line.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = value["controlPID"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let pid = Int32(exactly: number.doubleValue), pid > 0,
              let revision = value["playbackRevision"] as? String,
              let uuid = UUID(uuidString: revision),
              let action = value["command"] as? String else { return nil }
        context = SessionTicket(pid: pid, revision: uuid)
        var seekPosition: Double?
        switch action {
        case "play": command = 0
        case "pause": command = 1
        case "next": command = 4
        case "previous": command = 5
        case "seek":
            guard let seconds = value["position"] as? NSNumber,
                  CFGetTypeID(seconds) != CFBooleanGetTypeID(),
                  seconds.doubleValue.isFinite,
                  (0...604_800).contains(seconds.doubleValue) else { return nil }
            command = 24
            seekPosition = seconds.doubleValue
        default: return nil
        }
        position = seekPosition
    }
    func nativeCommand(supported: Set<Int32>?, playing: Bool?) -> Int32? {
        guard let supported else { return command }
        if supported.contains(command) { return command }
        // Toggle is safe only with a freshly known state for this exact session.
        if (command == 0 || command == 1), playing != nil, supported.contains(2) { return 2 }
        return nil
    }

}

struct PlaybackLineFramer {
    private var line = Data()
    private var discarding = false

    mutating func append(_ data: Data) -> [String] {
        var result: [String] = []
        for byte in data {
            if byte == 0x0A {
                if !discarding, let message = String(data: line, encoding: .utf8) { result.append(message) }
                line.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                if line.count >= 2_048 {
                    line.removeAll(keepingCapacity: true)
                    discarding = true
                } else { line.append(byte) }
            }
        }
        return result
    }
}
