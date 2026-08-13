import Foundation
import Testing

@testable import AnearCore

/// ConfigStore against a unique temp file per test — never the real
/// Application Support path.
struct ConfigStoreTests {
    /// Runs `body` with a store pointed at a unique temp config file,
    /// cleaning it up afterwards.
    private func withStore(_ body: (ConfigStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anear.config.tests.\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try body(ConfigStore(fileURL: fileURL), fileURL)
    }

    @Test func missingFileLoadsStarterAndWritesNothing() throws {
        try withStore { store, fileURL in
            let config = store.load()

            #expect(config == AnearConfig())
            #expect(config.lines == StarterPack.lines)
            #expect(config.minIntervalMinutes == 8)
            #expect(config.maxIntervalMinutes == 20)
            #expect(config.followCursor == false)
            // Loading must not create the file.
            #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
        }
    }

    @Test func saveThenLoadRoundTripsConfig() throws {
        try withStore { store, fileURL in
            let config = AnearConfig(
                lines: [
                    Line(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, text: "A."),
                    Line(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, text: "B."),
                ],
                minIntervalMinutes: 5,
                maxIntervalMinutes: 30,
                followCursor: true
            )

            try store.save(config)

            #expect(FileManager.default.fileExists(atPath: fileURL.path))
            #expect(store.load() == config)
        }
    }

    @Test func saveClampsInvalidMinutes() throws {
        try withStore { store, _ in
            let invalid = AnearConfig(
                lines: [Line(text: "x")],
                minIntervalMinutes: 0,
                maxIntervalMinutes: -5
            )

            try store.save(invalid)
            let loaded = store.load()

            #expect(loaded.minIntervalMinutes == 1)
            #expect(loaded.maxIntervalMinutes == 1)  // never below min
        }
    }

    @Test func loadClampsInvalidMinutesInHandWrittenFile() throws {
        try withStore { store, fileURL in
            let json = """
                {
                  "lines" : [
                    {
                      "id" : "11111111-1111-1111-1111-111111111111",
                      "text" : "hi"
                    }
                  ],
                  "minIntervalMinutes" : 0,
                  "maxIntervalMinutes" : 3
                }
                """
            try Data(json.utf8).write(to: fileURL)

            let loaded = store.load()

            #expect(loaded.minIntervalMinutes == 1)
            #expect(loaded.maxIntervalMinutes == 3)
        }
    }

    @Test func loadsHandWrittenFileWithoutFollowCursorKey() throws {
        try withStore { store, fileURL in
            // Config files written before `followCursor` existed carry no
            // such key; they must still decode, keeping lines and minutes,
            // with followCursor defaulting to false.
            let json = """
                {
                  "lines" : [
                    {
                      "id" : "11111111-1111-1111-1111-111111111111",
                      "text" : "hi"
                    }
                  ],
                  "minIntervalMinutes" : 3,
                  "maxIntervalMinutes" : 7
                }
                """
            try Data(json.utf8).write(to: fileURL)

            let loaded = store.load()

            #expect(loaded.followCursor == false)
            #expect(
                loaded.lines
                    == [
                        Line(
                            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                            text: "hi"
                        )
                    ]
            )
            #expect(loaded.minIntervalMinutes == 3)
            #expect(loaded.maxIntervalMinutes == 7)
        }
    }

    @Test func corruptFileLoadsStarterAndDefaults() throws {
        try withStore { store, fileURL in
            try Data("definitely not JSON".utf8).write(to: fileURL)

            #expect(store.load() == AnearConfig())
        }
    }

    @Test func saveAllowsEmptyLinesAndLoadRestoresStarter() throws {
        try withStore { store, fileURL in
            let empty = AnearConfig(lines: [], minIntervalMinutes: 8, maxIntervalMinutes: 20)
            try store.save(empty)

            // The file really contains `[]`, not the starter pack.
            let saved = try JSONDecoder().decode(
                AnearConfig.self,
                from: Data(contentsOf: fileURL)
            )
            #expect(saved.lines.isEmpty)

            // The next load restores the starter pack.
            let loaded = store.load()
            #expect(loaded.lines == StarterPack.lines)
            #expect(loaded.minIntervalMinutes == 8)
            #expect(loaded.maxIntervalMinutes == 20)
        }
    }

    @Test func defaultFileURLSitsUnderApplicationSupport() {
        let url = ConfigStore.defaultFileURL()
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        #expect(url.lastPathComponent == "config.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Anear")
        let expected =
            appSupport
            .appendingPathComponent("Anear", isDirectory: true)
            .appendingPathComponent("config.json")
        #expect(url.path == expected.path)
        #expect(url.deletingLastPathComponent().deletingLastPathComponent() == appSupport)
    }
}
