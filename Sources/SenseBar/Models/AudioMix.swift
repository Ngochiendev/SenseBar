import Foundation

/// Five fixed bands; the saved curve survives bypass without changing app volume.
struct AppEqualizer: Codable, Equatable, Sendable {
  static let frequencies = [60.0, 250, 1_000, 4_000, 12_000]
  var enabled = false
  var gains: [Float] = Array(repeating: 0, count: 5)
  var normalized: Self {
    var result = self
    result.gains = (0..<5).map { index in
      guard gains.indices.contains(index), gains[index].isFinite else { return 0 }
      return min(12, max(-12, gains[index]))
    }
    return result
  }
  var isEffective: Bool { enabled && normalized.gains.contains { abs($0) > 0.001 } }
  static let presets: [(vi: String, en: String, gains: [Float])] = [
    ("Nguyên bản", "Flat", [0, 0, 0, 0, 0]),
    ("Giọng nói", "Speech", [-3, -2, 1, 2, -1]),
    ("Ấm", "Warm", [2, 1, 0, -1, -2]),
    ("Bass nhẹ", "Gentle bass", [3, 1, 0, 0, 0]),
  ]
}

struct AppMixState: Codable, Equatable, Sendable {
  var volume: Double = 1
  var equalizer = AppEqualizer()
  var normalized: Self {
    Self(volume: volume.isFinite ? min(2, max(0, volume)) : 1, equalizer: equalizer.normalized)
  }
}

/// One versioned payload prevents volume and EQ histories from drifting apart.
struct AudioMixDocument: Codable, Sendable {
  var version = 1
  var states: [String: AppMixState] = [:]

  static func load(_ defaults: UserDefaults) -> Self {
    if let data = defaults.data(forKey: key),
      let decoded = try? JSONDecoder().decode(Self.self, from: data), decoded.version == 1 {
      var result = decoded
      result.states = decoded.states.filter { !$0.key.hasPrefix("pid:") }.mapValues(\.normalized)
      return result
    }
    let legacy = defaults.dictionary(forKey: "sensebar.audio.appVolumes") as? [String: Double] ?? [:]
    return Self(states: legacy.filter { !$0.key.hasPrefix("pid:") }.mapValues {
      AppMixState(volume: $0).normalized
    })
  }

  func save(_ defaults: UserDefaults) -> Bool {
    // Preserve unknown/newer or damaged payloads before replacing them.
    if let old = defaults.data(forKey: Self.key),
      (try? JSONDecoder().decode(Self.self, from: old))?.version != 1 {
      defaults.set(old, forKey: Self.key + ".recovery")
    }
    guard let data = try? JSONEncoder().encode(self) else { return false }
    defaults.set(data, forKey: Self.key)
    return true
  }
  /// Uses an isolated defaults domain; never touches a user's audio settings.
  static func validatePersistence() -> Bool {
    let suite = "SenseBar.MixSelfTest.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { return false }
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["com.example.player": 0.35, "pid:123": 1.8], forKey: "sensebar.audio.appVolumes")
    var document = load(defaults)
    guard document.states["com.example.player"]?.volume == 0.35,
      document.states["pid:123"] == nil else { return false }
    let curve = AppEqualizer(enabled: true, gains: [.nan, 100, -100]).normalized
    guard curve.gains == [0, 12, -12, 0, 0] else { return false }
    document.states["com.example.player"] = AppMixState(volume: 0, equalizer: curve)
    guard document.save(defaults) else { return false }
    let restored = load(defaults)
    guard restored.states == document.states else { return false }
    let damaged = Data("damaged".utf8)
    defaults.set(damaged, forKey: key)
    return document.save(defaults) && defaults.data(forKey: key + ".recovery") == damaged
  }

  private static let key = "sensebar.audio.mix.v1"
}
