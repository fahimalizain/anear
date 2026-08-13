import Foundation

/// Loads and saves the Anear config (lines, interval bounds, followCursor,
/// and holdSeconds) as pretty-printed JSON at
/// `~/Library/Application Support/Anear/config.json`.
///
/// Load precedence:
/// 1. The JSON file, if it exists and decodes (validated; empty lines fall
///    back to the starter pack; a missing `followCursor` key — old config
///    files — decodes as false; a missing `holdSeconds` key — config files
///    from before that field existed — defaults to
///    `OverlayTiming.holdDuration`, 4).
/// 2. Otherwise: fresh install — starter pack + 8/20, followCursor off,
///    holdSeconds 4. Loading never writes the file; only `save` does.
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

    public func load() -> AnearConfig {
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

        // 2. File missing or undecodable: starter pack + 8/20.
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
