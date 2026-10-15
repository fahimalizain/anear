import Foundation

/// UserDefaults is documented thread-safe but the Command-Line Tools SDK
/// doesn't mark it `Sendable` (the Xcode SDK does). Box it so the store can
/// declare `Sendable` cleanly on either toolchain.
private struct SendableUserDefaults: @unchecked Sendable {
    let value: UserDefaults
}

/// Persists the pause in UserDefaults as three small keys: the state name and,
/// for a timed pause, the menu duration plus its absolute wall-clock deadline
/// in epoch seconds, so a pause survives a relaunch without trusting an
/// in-memory countdown. The pre-upgrade `anear.paused` bool is kept in sync
/// too, so anything still reading the old key sees the truth.
///
/// Load precedence:
/// 1. `anear.pauseState` — exactly `"running"`, `"until"`, or `"indefinite"`.
/// 2. `"until"` additionally requires a `Double` deadline and a known
///    duration.
/// 3. Otherwise — an unrecognised value, or no state key at all, which is a
///    pre-upgrade install — the legacy `anear.paused` bool: true is
///    indefinite, false or absent is running.
///
/// An expired deadline reads as running, because a timed pause that outlived
/// its deadline is no longer a pause.
///
/// One fail-safe rule covers every gap in that table: **any missing or
/// unparseable component reads as running**. A half-written or corrupt store
/// must never leave the user permanently paused with no way back — the old
/// store's documented default ("a missing key reads as not paused") survives
/// unchanged. `load` never writes, exactly like `ConfigStore.load`: normalising
/// an expired deadline is the caller's to persist on its next tick.
public struct PauseStore: Sendable {
    private let defaults: SendableUserDefaults
    private let stateKey: String
    private let durationKey: String
    private let deadlineKey: String
    private let legacyKey: String

    public init(
        defaults: UserDefaults,
        stateKey: String = "anear.pauseState",
        durationKey: String = "anear.pauseDuration",
        deadlineKey: String = "anear.pauseUntil",
        legacyKey: String = "anear.paused"
    ) {
        self.defaults = SendableUserDefaults(value: defaults)
        self.stateKey = stateKey
        self.durationKey = durationKey
        self.deadlineKey = deadlineKey
        self.legacyKey = legacyKey
    }

    /// The persisted pause, normalised so a deadline that has already passed
    /// reads as running. A fresh suite, or one whose keys cannot be trusted,
    /// reads as running.
    public func load(at now: Date) -> PauseState {
        persisted().refreshed(at: now)
    }

    /// Writes the state keys for `state`, clearing the ones that do not apply
    /// so a stale deadline can never be mistaken for a live one, and keeps the
    /// legacy bool honest: true exactly while the pause is indefinite.
    public func save(_ state: PauseState) {
        switch state {
        case .running:
            defaults.value.set("running", forKey: stateKey)
            defaults.value.removeObject(forKey: durationKey)
            defaults.value.removeObject(forKey: deadlineKey)
        case .until(let duration, let deadline):
            defaults.value.set("until", forKey: stateKey)
            defaults.value.set(duration.rawValue, forKey: durationKey)
            // Epoch seconds: an absolute instant, so nothing has to count
            // down while the app is not running.
            defaults.value.set(deadline.timeIntervalSince1970, forKey: deadlineKey)
        case .indefinite:
            defaults.value.set("indefinite", forKey: stateKey)
            defaults.value.set(PauseDuration.indefinitely.rawValue, forKey: durationKey)
            defaults.value.removeObject(forKey: deadlineKey)
        }
        defaults.value.set(state == .indefinite, forKey: legacyKey)
    }

    /// The state exactly as stored, without the expiry normalisation, so
    /// `load` has a single place to apply the fail-safe rule.
    private func persisted() -> PauseState {
        switch defaults.value.string(forKey: stateKey) {
        case "running":
            return .running
        case "indefinite":
            return .indefinite
        case "until":
            // `object(forKey:)`, not `double(forKey:)`: the latter reads 0 for
            // a missing key, indistinguishable from a real epoch-0 deadline.
            // `.indefinitely` is rejected as a duration because `.until` must
            // never carry it.
            guard let epoch = defaults.value.object(forKey: deadlineKey) as? Double,
                let rawDuration = defaults.value.string(forKey: durationKey),
                let duration = PauseDuration(rawValue: rawDuration),
                duration != .indefinitely
            else {
                return .running
            }
            return .until(duration, deadline: Date(timeIntervalSince1970: epoch))
        default:
            // No state key at all (a pre-upgrade install) or an unrecognised
            // one: the legacy bool is the only truth available, and reading it
            // is exactly what the old store did.
            return defaults.value.bool(forKey: legacyKey) ? .indefinite : .running
        }
    }
}
