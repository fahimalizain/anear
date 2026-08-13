import Foundation
import Testing

@testable import AnearCore

struct PauseStoreTests {
    private let key = "anear.paused"

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

    @Test func freshSuiteLoadsNotPaused() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults, key: key)

            #expect(store.load() == false)
        }
    }

    @Test func saveTrueThenFalseRoundTrips() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults, key: key)

            store.save(true)
            #expect(store.load() == true)

            store.save(false)
            #expect(store.load() == false)
        }
    }

    @Test func secondStoreSeesSavedValue() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults, key: key)
            store.save(true)

            // A second store over the same suite sees the same state.
            let reloaded = PauseStore(defaults: defaults, key: key)
            #expect(reloaded.load() == true)
        }
    }
}
