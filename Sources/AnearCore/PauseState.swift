import Foundation

/// The pause lengths the status menu offers. The raw value of each case is
/// persisted in UserDefaults under `anear.pauseDuration` — treat it as a wire
/// format: renaming a case would strand a saved pause, so any rename needs a
/// migration.
public enum PauseDuration: String, CaseIterable, Sendable {
    case fifteenMinutes
    case oneHour
    case threeHours
    case today
    case indefinitely

    /// The menu title for this duration, so the menu reads straight off the
    /// domain model instead of keeping a parallel list of strings.
    public var title: String {
        switch self {
        case .fifteenMinutes: return "15 Minutes"
        case .oneHour: return "1 Hour"
        case .threeHours: return "3 Hours"
        case .today: return "Today"
        case .indefinitely: return "Indefinitely"
        }
    }

    /// The instant this duration ends at, or `nil` for `.indefinitely`.
    ///
    /// `today` is the *next* midnight in `calendar` (the start of tomorrow).
    /// That is calendar arithmetic, not `now + 86_400`: a day is 23 or 25
    /// hours long across a DST change, and only the calendar knows which. The
    /// fixed lengths are plain wall-clock seconds and deliberately are not
    /// calendar-aware.
    public func deadline(from now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .fifteenMinutes: return now.addingTimeInterval(15 * 60)
        case .oneHour: return now.addingTimeInterval(60 * 60)
        case .threeHours: return now.addingTimeInterval(3 * 60 * 60)
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            // `date(byAdding:)` is optional, but a Gregorian calendar can
            // always add a day. Fall back to the fixed 24h offset instead of
            // trapping — a pause that ends an hour late beats a crash.
            return calendar.date(byAdding: .day, value: 1, to: startOfDay)
                ?? startOfDay.addingTimeInterval(86_400)
        case .indefinitely: return nil
        }
    }
}

/// Which pause is in effect, if any. `.until` carries both the absolute
/// wall-clock deadline and the menu duration that produced it, so the menu can
/// still tick the option the user actually chose after a relaunch.
///
/// This is a plain value type: `started(_:at:calendar:)` starts a pause and
/// `refreshed(at:)` ends one whose deadline has passed. Nothing here reads a
/// clock or runs a timer — `now` and `calendar` are injected, mirroring how
/// `SparseScheduler` injects `now`, so the state machine composes on top of
/// the scheduler without changing it.
public enum PauseState: Equatable, Sendable {
    case running
    /// `duration` is never `.indefinitely` here: timed state is built through
    /// `started(_:at:calendar:)`, which maps `.indefinitely` to `.indefinite`.
    case until(PauseDuration, deadline: Date)
    case indefinite

    /// The one supported way to start a pause. `.indefinitely` becomes
    /// `.indefinite`; every other duration becomes `.until` carrying both the
    /// duration and the deadline it resolves to.
    public static func started(
        _ duration: PauseDuration,
        at now: Date,
        calendar: Calendar
    ) -> PauseState {
        guard let deadline = duration.deadline(from: now, calendar: calendar) else {
            return .indefinite
        }
        return .until(duration, deadline: deadline)
    }

    /// True for a timed and for an indefinite pause; false while running.
    public var isPaused: Bool {
        switch self {
        case .running: return false
        case .until, .indefinite: return true
        }
    }

    /// The menu option to tick for this state, or `nil` while running. An
    /// indefinite pause ticks `Indefinitely`; a timed pause ticks the duration
    /// that started it.
    public var tickedDuration: PauseDuration? {
        switch self {
        case .running: return nil
        case .until(let duration, _): return duration
        case .indefinite: return .indefinitely
        }
    }

    /// Seconds until the pause ends; `nil` while running or indefinite, since
    /// neither has an end to count down to. Negative once `now` is past the
    /// deadline — the caller normally refreshes first, but a countdown must
    /// never pretend there is more time left than there is.
    public func remaining(at now: Date) -> TimeInterval? {
        guard case .until(_, let deadline) = self else { return nil }
        return deadline.timeIntervalSince(now)
    }

    /// The auto-expiry rule: a timed pause whose deadline has arrived
    /// (`now >= deadline`) reads as running, so expiry needs no timer of its
    /// own — the app just re-reads the state. Running and indefinite are
    /// returned unchanged: an indefinite pause never expires by itself.
    public func refreshed(at now: Date) -> PauseState {
        guard case .until(_, let deadline) = self else { return self }
        return now >= deadline ? .running : self
    }
}
