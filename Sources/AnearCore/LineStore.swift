import Foundation

/// UserDefaults is documented thread-safe but the Command-Line Tools SDK
/// doesn't mark it `Sendable` (the Xcode SDK does). Box it so the store can
/// declare `Sendable` cleanly on either toolchain.
private struct SendableUserDefaults: @unchecked Sendable {
    let value: UserDefaults
}

/// Persists the user's lines in UserDefaults as JSON under a single key.
/// A missing, empty, or undecodable key falls back to `StarterPack.lines`;
/// the fallback is never written to disk — only `save` persists.
public struct UserDefaultsLineStore: Sendable {
    private let defaults: SendableUserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "anear.lines") {
        self.defaults = SendableUserDefaults(value: defaults)
        self.key = key
    }

    public func load() -> [Line] {
        guard let data = defaults.value.data(forKey: key),
            let lines = try? JSONDecoder().decode([Line].self, from: data),
            !lines.isEmpty
        else {
            return StarterPack.lines
        }
        return lines
    }

    public func save(_ lines: [Line]) {
        guard let data = try? JSONEncoder().encode(lines) else { return }
        defaults.value.set(data, forKey: key)
    }
}
