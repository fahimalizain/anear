import Foundation

/// Loads and saves the Anear config (lines + interval bounds) as pretty-
/// printed JSON at `~/Library/Application Support/Anear/config.json`.
///
/// Load precedence:
/// 1. The JSON file, if it exists and decodes (validated; empty lines fall
///    back to the starter pack).
/// 2. The legacy UserDefaults lines (`anear.lines`), migrated from the
///    pre-JSON `UserDefaultsLineStore` — with default 8/20 bounds. Loading
///    never writes the file; only `save` does.
/// 3. Fresh install: starter pack + 8/20.
public struct ConfigStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The config file for a normal install:
    /// Application Support/Anear/config.json.
    public static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Anear", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    public func load(migratingFrom defaults: UserDefaults = .standard) -> AnearConfig {
        // 1. Existing file wins: decode, clamp minutes, restore starter
        //    lines when the saved list is empty.
        if let data = try? Data(contentsOf: fileURL),
            var config = try? JSONDecoder().decode(AnearConfig.self, from: data)
        {
            config.validate()
            if config.lines.isEmpty {
                config.lines = StarterPack.lines
            }
            return config
        }

        // 2. Legacy migration: the user's lines from UserDefaults with the
        //    default 8/20 bounds. Falls back to the starter pack when the
        //    key is missing, empty, or undecodable.
        let legacyLines = UserDefaultsLineStore(defaults: defaults).load()
        if !legacyLines.isEmpty {
            return AnearConfig(
                lines: legacyLines,
                minIntervalMinutes: 8,
                maxIntervalMinutes: 20
            )
        }

        // 3. Fresh install.
        return AnearConfig()
    }

    /// Writes `config` to `fileURL`, creating intermediate directories as
    /// needed. Minutes are validated before writing; an empty `lines` list
    /// is written as-is (`[]`) — the next load restores the starter pack.
    public func save(_ config: AnearConfig) throws {
        var validated = config
        validated.validate()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated)
        try data.write(to: fileURL, options: .atomic)
    }
}
