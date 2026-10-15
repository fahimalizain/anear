import Foundation
import Testing

@testable import AnearCore

/// `PauseState` as a pure value: start, count down, refresh to expiry. Every
/// test injects `now` and a fixed calendar, mirroring `SparseSchedulerTests`.
struct PauseStateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func isPausedIsTrueForBothKindsOfPause() {
        #expect(PauseState.running.isPaused == false)
        #expect(PauseState.until(.oneHour, deadline: now.addingTimeInterval(3600)).isPaused)
        #expect(PauseState.indefinite.isPaused)
    }

    @Test func remainingCountsDownToTheDeadline() {
        let deadline = now.addingTimeInterval(3 * 3600)
        let state = PauseState.until(.threeHours, deadline: deadline)

        #expect(state.remaining(at: now) == 10_800)
        #expect(state.remaining(at: now.addingTimeInterval(3600)) == 7200)
        // At and past the deadline the wait is zero or negative rather than
        // nil: nil means "no end to count down to", which a timed pause has
        // even when it is over. The caller refreshes before displaying it.
        #expect(state.remaining(at: deadline) == 0)
        #expect(state.remaining(at: deadline.addingTimeInterval(5)) == -5)
    }

    @Test func runningAndIndefiniteHaveNoRemainingTime() {
        let decadesLater = now.addingTimeInterval(20 * 365 * 86_400)

        #expect(PauseState.running.remaining(at: now) == nil)
        #expect(PauseState.indefinite.remaining(at: now) == nil)
        #expect(PauseState.indefinite.remaining(at: decadesLater) == nil)
    }

    @Test func startedMapsIndefinitelyToIndefinite() {
        #expect(PauseState.started(.indefinitely, at: now, calendar: calendar) == .indefinite)
    }

    @Test func startedBuildsTimedStateFromTheDuration() {
        #expect(
            PauseState.started(.fifteenMinutes, at: now, calendar: calendar)
                == .until(.fifteenMinutes, deadline: now.addingTimeInterval(900))
        )
    }

    @Test func refreshedExpiresAPastDeadline() {
        let state = PauseState.until(.oneHour, deadline: now.addingTimeInterval(-1))

        #expect(state.refreshed(at: now) == .running)
    }

    @Test func refreshedExpiresExactlyAtTheDeadline() {
        // The boundary is `now >= deadline`, so the deadline instant itself is
        // already over — a pause must never linger for one more tick.
        let state = PauseState.until(.oneHour, deadline: now)

        #expect(state.refreshed(at: now) == .running)
    }

    @Test func refreshedKeepsAFutureDeadlineIntact() {
        let deadline = now.addingTimeInterval(3600)
        let state = PauseState.until(.oneHour, deadline: deadline)

        let refreshed = state.refreshed(at: now.addingTimeInterval(3599))

        // Both the duration and the exact deadline survive, so the menu can
        // still tick the option the user chose.
        #expect(refreshed == .until(.oneHour, deadline: deadline))
    }

    @Test func refreshedNeverExpiresAnIndefinitePause() {
        let state = PauseState.indefinite
        // Two decades of uptime later it is still paused: only the user ends
        // an indefinite pause.
        let decadesLater = now.addingTimeInterval(20 * 365 * 86_400)

        #expect(state.refreshed(at: now) == .indefinite)
        #expect(state.refreshed(at: decadesLater) == .indefinite)
    }

    @Test func refreshedLeavesRunningAlone() {
        #expect(PauseState.running.refreshed(at: now) == .running)
    }

    @Test func refreshedIsIdempotent() {
        let deadline = now.addingTimeInterval(900)
        let states: [PauseState] = [
            .running,
            .indefinite,
            .until(.fifteenMinutes, deadline: deadline.addingTimeInterval(-1)),
            .until(.fifteenMinutes, deadline: deadline),
            .until(.fifteenMinutes, deadline: deadline.addingTimeInterval(1)),
        ]
        let instants = [now, deadline, deadline.addingTimeInterval(86_400)]

        for state in states {
            for instant in instants {
                let once = state.refreshed(at: instant)
                #expect(once.refreshed(at: instant) == once)
            }
        }
    }

    @Test func tickedDurationNamesTheOptionThatStartedThePause() {
        let deadline = now.addingTimeInterval(3 * 3600)

        #expect(PauseState.running.tickedDuration == nil)
        #expect(PauseState.indefinite.tickedDuration == .indefinitely)
        #expect(
            PauseState.until(.fifteenMinutes, deadline: deadline).tickedDuration
                == .fifteenMinutes
        )
        #expect(PauseState.until(.oneHour, deadline: deadline).tickedDuration == .oneHour)
        #expect(PauseState.until(.threeHours, deadline: deadline).tickedDuration == .threeHours)
        // The duration is the one carried in the state, not one recomputed
        // from the deadline: this deadline is three hours out, which no
        // calendar would read as `Today`, and the menu must still tick the
        // option the user actually chose.
        #expect(PauseState.until(.today, deadline: deadline).tickedDuration == .today)
    }
}
