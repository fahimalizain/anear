import Foundation

/// The user-editable Anear configuration: the ambient lines, the sparse
/// scheduler's interval bounds in minutes, and whether the pill follows the
/// pointer while visible. Persisted as pretty-printed JSON at
/// `~/Library/Application Support/Anear/config.json` (see `ConfigStore`).
/// The pause and login-item flags are runtime state and deliberately live in
/// UserDefaults, not here.
public struct AnearConfig: Sendable, Equatable, Codable {
    public var lines: [Line]
    public var minIntervalMinutes: Int
    public var maxIntervalMinutes: Int
    /// Whether the pill tracks the pointer while visible. Off by default so
    /// the pinned-at-spawn behavior stays unchanged.
    public var followCursor: Bool

    public init(
        lines: [Line] = StarterPack.lines,
        minIntervalMinutes: Int = 8,
        maxIntervalMinutes: Int = 20,
        followCursor: Bool = false
    ) {
        self.lines = lines
        self.minIntervalMinutes = minIntervalMinutes
        self.maxIntervalMinutes = maxIntervalMinutes
        self.followCursor = followCursor
    }

    /// Config files written by older Anear versions predate `followCursor`.
    /// A missing key must decode as `false` rather than fail the whole
    /// decode, which would otherwise silently discard the user's lines and
    /// interval for the starter pack. `encode(to:)` stays synthesized and
    /// always writes the key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lines = try container.decode([Line].self, forKey: .lines)
        minIntervalMinutes = try container.decode(Int.self, forKey: .minIntervalMinutes)
        maxIntervalMinutes = try container.decode(Int.self, forKey: .maxIntervalMinutes)
        followCursor = try container.decodeIfPresent(Bool.self, forKey: .followCursor) ?? false
    }

    /// Clamps the interval bounds so the schedule is always sane:
    /// `min` is at least 1 and `max` is never below `min`. Applied on both
    /// load and save. Empty `lines` is *not* touched here: saving an empty
    /// list is allowed (the next load restores the starter pack).
    public mutating func validate() {
        minIntervalMinutes = max(1, minIntervalMinutes)
        maxIntervalMinutes = max(minIntervalMinutes, maxIntervalMinutes)
    }

    public var minIntervalSeconds: TimeInterval {
        TimeInterval(minIntervalMinutes * 60)
    }

    public var maxIntervalSeconds: TimeInterval {
        TimeInterval(maxIntervalMinutes * 60)
    }
}
