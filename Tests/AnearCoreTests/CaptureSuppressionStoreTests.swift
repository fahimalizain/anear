import Foundation
import Testing

@testable import AnearCore

/// `CaptureSuppressionStore` against a unique UserDefaults suite per test —
/// never `UserDefaults.standard` — covering the default-on rule and the
/// explicit-off round trip.
struct CaptureSuppressionStoreTests {
    private let key = "anear.suppressWhileCaptured"

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

    @Test func freshSuiteIsEnabled() throws {
        try withSuite { defaults in
            let store = CaptureSuppressionStore(defaults: defaults)

            // No key at all: the feature is on, unlike a plain bool read,
            // which would call a missing key false.
            #expect(defaults.object(forKey: key) == nil)
            #expect(store.isEnabled())
        }
    }

    @Test func disablingSurvivesASecondStore() throws {
        try withSuite { defaults in
            CaptureSuppressionStore(defaults: defaults).setEnabled(false)

            #expect(CaptureSuppressionStore(defaults: defaults).isEnabled() == false)
        }
    }

    @Test func enablingRoundTrips() throws {
        try withSuite { defaults in
            let store = CaptureSuppressionStore(defaults: defaults)

            store.setEnabled(false)
            store.setEnabled(true)

            // A real Bool, so the value stays readable and greppable.
            #expect(defaults.object(forKey: key) as? Bool == true)
            #expect(store.isEnabled())
            #expect(CaptureSuppressionStore(defaults: defaults).isEnabled())
        }
    }

    @Test func stringValueReadsAsEnabled() throws {
        try withSuite { defaults in
            defaults.set("false", forKey: key)

            // Junk, not a decision: only an explicit `false` turns this off,
            // because the default is on and a corrupt store must not quietly
            // start showing lines mid-call.
            #expect(CaptureSuppressionStore(defaults: defaults).isEnabled())
        }
    }

    @Test func disablingWritesTheDefaultKey() throws {
        try withSuite { defaults in
            CaptureSuppressionStore(defaults: defaults).setEnabled(false)

            #expect(defaults.object(forKey: "anear.suppressWhileCaptured") as? Bool == false)
        }
    }
}
