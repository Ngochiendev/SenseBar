import Foundation

/// Never redirect an explicit media source to another app's EQ.
enum AudioEqualizerTarget {
  static func resolve(preferredID: String?, eligibleIDs: [String], playingIDs: [String]) -> String? {
    if let preferredID, !preferredID.isEmpty {
      let matches = eligibleIDs.filter { $0.caseInsensitiveCompare(preferredID) == .orderedSame }
      return matches.count == 1 ? matches[0] : nil
    }
    let playing = eligibleIDs.filter { playingIDs.contains($0) }
    return playing.count == 1 ? playing[0] : nil
  }
}
