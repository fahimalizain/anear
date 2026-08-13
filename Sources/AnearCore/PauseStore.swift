import Foundation

/// UserDefaults is documented thread-safe but the Command-Line Tools SDK
/// doesn't mark it `Sendable` (the Xcode SDK does). Box it so the store can
/// declare `Sendable` cleanly on either toolchain. (Same pattern as
/// `UserDefaultsLineStore`.)
private struct SendableUserDefaults: @unchecked Sendable {
    let value: UserDefaults
}

/// Persists the paused state in UserDefaults as a Bool under a single key.
/// A missing key reads as not paused — the default is running.
public struct PauseStore: Sendable {
    private let defaults: SendableUserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "anear.paused") {
        self.defaults = SendableUserDefaults(value: defaults)
        self.key = key
    }

    /// True when the user paused; a missing key reads as false.
    public func load() -> Bool {
        defaults.value.bool(forKey: key)
    }

    public func save(_ paused: Bool) {
        defaults.value.set(paused, forKey: key)
    }
}
