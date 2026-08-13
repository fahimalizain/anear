import Foundation

/// The user-editable Anear configuration: the ambient lines plus the sparse
/// scheduler's interval bounds in minutes. Persisted as pretty-printed JSON
/// at `~/Library/Application Support/Anear/config.json` (see `ConfigStore`).
/// The pause and login-item flags are runtime state and deliberately live in
/// UserDefaults, not here.
public struct AnearConfig: Sendable, Equatable, Codable {
    public var lines: [Line]
    public var minIntervalMinutes: Int
    public var maxIntervalMinutes: Int

    public init(
        lines: [Line] = StarterPack.lines,
        minIntervalMinutes: Int = 8,
        maxIntervalMinutes: Int = 20
    ) {
        self.lines = lines
        self.minIntervalMinutes = minIntervalMinutes
        self.maxIntervalMinutes = maxIntervalMinutes
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
