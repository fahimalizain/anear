import Testing
import Foundation
@testable import AnearCore

struct LineStoreTests {
    private let key = "anear.lines"

    /// Runs `body` with a fresh, unique UserDefaults suite — never
    /// `UserDefaults.standard` — and cleans the suite up afterwards.
    private func withSuite(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "anear.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create test suite \(suiteName)")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test func freshSuiteLoadsStarterPackWithoutWriting() throws {
        try withSuite { defaults in
            let store = UserDefaultsLineStore(defaults: defaults, key: key)

            #expect(store.load() == StarterPack.lines)
            // Loading must not write anything for the key.
            #expect(defaults.data(forKey: key) == nil)
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test func saveThenLoadRoundTripsCustomLines() throws {
        try withSuite { defaults in
            let store = UserDefaultsLineStore(defaults: defaults, key: key)
            let custom = [
                Line(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, text: "My own line."),
                Line(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, text: "Another one."),
            ]

            store.save(custom)

            #expect(store.load() == custom)
            // A second store over the same suite sees the same data.
            let reloaded = UserDefaultsLineStore(defaults: defaults, key: key)
            #expect(reloaded.load() == custom)
        }
    }

    @Test func corruptDataFallsBackToStarterPack() throws {
        try withSuite { defaults in
            // Garbage bytes under the key.
            defaults.set(Data("definitely not JSON".utf8), forKey: key)

            let store = UserDefaultsLineStore(defaults: defaults, key: key)
            #expect(store.load() == StarterPack.lines)
        }
    }
}
