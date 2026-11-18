import Foundation

/// UserDefaults is documented thread-safe but the Command-Line Tools SDK
/// doesn't mark it `Sendable` (the Xcode SDK does). Box it so the store can
/// declare `Sendable` cleanly on either toolchain. Deliberately a copy of the
/// box in `PauseStore` rather than a shared type: one file's `private` helper
/// is not worth a cross-file abstraction that exists only for a toolchain gap.
private struct SendableUserDefaults: @unchecked Sendable {
    let value: UserDefaults
}

/// Persists the user's "don't show lines while the screen is captured"
/// preference — one bool, in UserDefaults rather than `config.json`, because it
/// is runtime behaviour a user toggles from the menu, like pause and
/// start-at-login, not a line or an interval.
///
/// The preference defaults **on**: a first run, or a value that cannot be read
/// as a bool, reads as enabled. Only an explicit `false` turns it off, so a
/// corrupt or half-written store can never silently switch the feature off and
/// leave lines landing mid-call.
public struct CaptureSuppressionStore: Sendable {
    private let defaults: SendableUserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "anear.suppressWhileCaptured") {
        self.defaults = SendableUserDefaults(value: defaults)
        self.key = key
    }

    /// True unless the stored value is explicitly `false`. `bool(forKey:)` is
    /// not enough on its own — it returns `false` for a missing key, which
    /// would invert this feature's default — so read the object and treat
    /// anything that is not a `Bool` as "leave it on".
    public func isEnabled() -> Bool {
        guard let stored = defaults.value.object(forKey: key) as? Bool else { return true }
        return stored
    }

    /// Writes a real `Bool` so `isEnabled` reads back exactly what was set.
    public func setEnabled(_ enabled: Bool) {
        defaults.value.set(enabled, forKey: key)
    }
}
