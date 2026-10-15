import Foundation
import Testing

@testable import AnearCore

/// `PauseStore` against a unique UserDefaults suite per test — never
/// `UserDefaults.standard` — covering the wire keys, the migration from the
/// legacy `anear.paused` bool, and the fail-safe reads.
struct PauseStoreTests {
    private let stateKey = "anear.pauseState"
    private let durationKey = "anear.pauseDuration"
    private let deadlineKey = "anear.pauseUntil"
    private let legacyKey = "anear.paused"

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

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

    @Test func freshSuiteLoadsRunning() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults)

            #expect(store.load(at: now) == .running)
        }
    }

    @Test func roundTripsEveryStateThroughASecondStore() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults)
            let deadline = now.addingTimeInterval(3 * 3600)
            let states: [PauseState] = [
                .running,
                .indefinite,
                .until(.threeHours, deadline: deadline),
            ]

            for state in states {
                store.save(state)
                #expect(store.load(at: now) == state)

                // A second store over the same suite sees the same state, so a
                // pause survives a relaunch with no shared memory.
                let reloaded = PauseStore(defaults: defaults)
                #expect(reloaded.load(at: now) == state)
            }
        }
    }

    @Test func savingWritesTheWireKeys() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults)
            let deadline = now.addingTimeInterval(900)

            store.save(.until(.fifteenMinutes, deadline: deadline))

            // Strings and a Double, not an archived blob, so the suite stays
            // readable and greppable.
            #expect(defaults.string(forKey: stateKey) == "until")
            #expect(defaults.string(forKey: durationKey) == "fifteenMinutes")
            let epoch = defaults.object(forKey: deadlineKey) as? Double
            #expect(epoch == deadline.timeIntervalSince1970)
        }
    }

    @Test func saveRunningClearsTheTimedKeys() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults)
            store.save(.until(.oneHour, deadline: now.addingTimeInterval(3600)))

            store.save(.running)

            #expect(defaults.string(forKey: stateKey) == "running")
            #expect(defaults.object(forKey: deadlineKey) == nil)
            #expect(defaults.object(forKey: durationKey) == nil)
        }
    }

    @Test func saveIndefiniteClearsTheDeadlineAndKeepsTheDuration() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults)
            store.save(.until(.oneHour, deadline: now.addingTimeInterval(3600)))

            store.save(.indefinite)

            #expect(defaults.string(forKey: stateKey) == "indefinite")
            // A stale deadline must not survive into the next state, but the
            // duration is what marks an indefinite pause.
            #expect(defaults.object(forKey: deadlineKey) == nil)
            #expect(defaults.string(forKey: durationKey) == "indefinitely")
        }
    }

    @Test func legacyPausedTrueMigratesToIndefinite() throws {
        try withSuite { defaults in
            // A pre-upgrade install: the old bool, no `pauseState` key.
            defaults.set(true, forKey: legacyKey)

            #expect(PauseStore(defaults: defaults).load(at: now) == .indefinite)
        }
    }

    @Test func legacyPausedFalseMigratesToRunning() throws {
        try withSuite { defaults in
            defaults.set(false, forKey: legacyKey)

            #expect(PauseStore(defaults: defaults).load(at: now) == .running)
        }
    }

    @Test func absentLegacyKeyLoadsRunning() throws {
        try withSuite { defaults in
            #expect(defaults.object(forKey: legacyKey) == nil)

            #expect(PauseStore(defaults: defaults).load(at: now) == .running)
        }
    }

    @Test func legacyBoolTracksTheState() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults)

            store.save(.indefinite)
            #expect(defaults.object(forKey: legacyKey) as? Bool == true)

            store.save(.running)
            #expect(defaults.object(forKey: legacyKey) as? Bool == false)

            store.save(.until(.oneHour, deadline: now.addingTimeInterval(3600)))
            #expect(defaults.object(forKey: legacyKey) as? Bool == false)
        }
    }

    @Test func expiredTimedPauseLoadsRunning() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults)
            // Saved while live, then the clock passed the deadline.
            store.save(.until(.oneHour, deadline: now.addingTimeInterval(-1)))

            #expect(defaults.string(forKey: stateKey) == "until")
            #expect(store.load(at: now) == .running)
        }
    }

    @Test func loadNeverWritesTheNormalisedStateBack() throws {
        try withSuite { defaults in
            let store = PauseStore(defaults: defaults)
            let deadline = now.addingTimeInterval(-1)
            store.save(.until(.fifteenMinutes, deadline: deadline))

            #expect(store.load(at: now) == .running)

            // Load is read-only, exactly like `ConfigStore.load`: the expired
            // record stays on disk as it was written. The app persists the
            // transition with `save` on a later tick, so a read can never
            // surprise a concurrent writer.
            #expect(defaults.string(forKey: stateKey) == "until")
            #expect(defaults.string(forKey: durationKey) == "fifteenMinutes")
            let epoch = defaults.object(forKey: deadlineKey) as? Double
            #expect(epoch == deadline.timeIntervalSince1970)
        }
    }

    @Test func untilWithoutADeadlineFallsBackToRunning() throws {
        try withSuite { defaults in
            defaults.set("until", forKey: stateKey)
            defaults.set("oneHour", forKey: durationKey)

            #expect(PauseStore(defaults: defaults).load(at: now) == .running)
        }
    }

    @Test func untilWithANonNumericDeadlineFallsBackToRunning() throws {
        try withSuite { defaults in
            defaults.set("until", forKey: stateKey)
            defaults.set("oneHour", forKey: durationKey)
            defaults.set("soon", forKey: deadlineKey)

            #expect(PauseStore(defaults: defaults).load(at: now) == .running)
        }
    }

    @Test func untilWithAnUnknownDurationFallsBackToRunning() throws {
        try withSuite { defaults in
            defaults.set("until", forKey: stateKey)
            defaults.set("whenever", forKey: durationKey)
            defaults.set(now.addingTimeInterval(3600).timeIntervalSince1970, forKey: deadlineKey)

            #expect(PauseStore(defaults: defaults).load(at: now) == .running)
        }
    }

    @Test func untilWithAnIndefiniteDurationFallsBackToRunning() throws {
        try withSuite { defaults in
            // `.until` must never carry `.indefinitely`, so this pair is
            // corrupt rather than a clever way to spell an indefinite pause.
            defaults.set("until", forKey: stateKey)
            defaults.set("indefinitely", forKey: durationKey)
            defaults.set(now.addingTimeInterval(3600).timeIntervalSince1970, forKey: deadlineKey)

            #expect(PauseStore(defaults: defaults).load(at: now) == .running)
        }
    }

    @Test func unrecognisedStateFallsBackToTheLegacyBool() throws {
        try withSuite { defaults in
            defaults.set("whenever", forKey: stateKey)
            defaults.set(true, forKey: legacyKey)

            #expect(PauseStore(defaults: defaults).load(at: now) == .indefinite)
        }
    }

    @Test func unrecognisedStateWithoutLegacyPauseLoadsRunning() throws {
        try withSuite { defaults in
            defaults.set("whenever", forKey: stateKey)
            defaults.set(false, forKey: legacyKey)

            #expect(PauseStore(defaults: defaults).load(at: now) == .running)
        }
    }

    @Test func leftoverTimedKeysWithoutAStateKeyLoadRunning() throws {
        try withSuite { defaults in
            // Garbage from a half-written store: a live-looking deadline and a
            // duration survive, but the state key does not.
            defaults.set(now.addingTimeInterval(3600).timeIntervalSince1970, forKey: deadlineKey)
            defaults.set("threeHours", forKey: durationKey)
            defaults.set(false, forKey: legacyKey)

            #expect(PauseStore(defaults: defaults).load(at: now) == .running)

            // The same leftovers with no legacy key at all: still running.
            defaults.removeObject(forKey: legacyKey)
            #expect(PauseStore(defaults: defaults).load(at: now) == .running)
        }
    }
}
