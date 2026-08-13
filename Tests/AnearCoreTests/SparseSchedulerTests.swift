import Testing
import Foundation
@testable import AnearCore

/// SparseScheduler with a fake clock and a fixed interval, so every test is
/// fully deterministic: `now` is a box the test mutates between ticks.
struct SparseSchedulerTests {
    private final class Clock: @unchecked Sendable {
        var now: TimeInterval = 0
    }

    private func makeScheduler(clock: Clock, interval: TimeInterval) -> SparseScheduler {
        SparseScheduler(
            now: { clock.now },
            nextInterval: { interval }
        )
    }

    @Test func initDoesNotFireAndFirstTickAtT0IsFalse() {
        let clock = Clock()
        var scheduler = makeScheduler(clock: clock, interval: 480)

        // Init rolls 480s remaining; a tick with zero elapsed must not fire.
        #expect(scheduler.tick(isPresent: true) == false)
        #expect(scheduler.isPaused == false)
    }

    @Test func firesExactlyWhenTheIntervalElapses() {
        let clock = Clock()
        var scheduler = makeScheduler(clock: clock, interval: 480)

        clock.now = 479
        #expect(scheduler.tick(isPresent: true) == false)

        clock.now = 480
        #expect(scheduler.tick(isPresent: true) == true)

        // A fresh 480s interval started at t=480, so the same instant is
        // back to full remaining and must not fire again.
        clock.now = 480
        #expect(scheduler.tick(isPresent: true) == false)
    }

    @Test func firesAtEachIntervalWithNoExtrasInBetween() {
        let clock = Clock()
        var scheduler = makeScheduler(clock: clock, interval: 480)

        clock.now = 479
        #expect(scheduler.tick(isPresent: true) == false)

        clock.now = 480
        #expect(scheduler.tick(isPresent: true) == true)

        clock.now = 959
        #expect(scheduler.tick(isPresent: true) == false)

        clock.now = 960
        #expect(scheduler.tick(isPresent: true) == true)
    }

    @Test func idleFreezesCountdownAndNeverBacklogs() {
        let clock = Clock()
        var scheduler = makeScheduler(clock: clock, interval: 480)

        // 60s remaining.
        clock.now = 420
        #expect(scheduler.tick(isPresent: true) == false)

        // 1800s away and still absent: frozen, no fire, no drain.
        clock.now = 2220
        #expect(scheduler.tick(isPresent: false) == false)
        clock.now = 4020
        #expect(scheduler.tick(isPresent: false) == false)

        // Back: only the leftover 60s count, so exactly one fire — not a
        // burst for the whole absence.
        clock.now = 4080
        #expect(scheduler.tick(isPresent: true) == true)
    }

    @Test func pauseFreezesAndResumeRollsAFreshInterval() {
        let clock = Clock()
        var scheduler = makeScheduler(clock: clock, interval: 480)

        // 1s remaining.
        clock.now = 479
        #expect(scheduler.tick(isPresent: true) == false)

        scheduler.setPaused(true)
        #expect(scheduler.isPaused)

        // 3600s of present time while paused: no fire (remaining is
        // irrelevant while paused).
        clock.now = 4079
        #expect(scheduler.tick(isPresent: true) == false)

        // Resume rolls a fresh 480s from now; no immediate fire.
        scheduler.setPaused(false)
        #expect(scheduler.isPaused == false)
        #expect(scheduler.tick(isPresent: true) == false)

        // A full fresh interval of present time → exactly one fire.
        clock.now = 4559
        #expect(scheduler.tick(isPresent: true) == true)
    }

    @Test func setPausedItselfNeverFires() {
        let clock = Clock()
        var scheduler = makeScheduler(clock: clock, interval: 480)

        // Huge elapsed time before pausing; pause must not fire.
        clock.now = 999_999
        scheduler.setPaused(true)

        // Unpause with the clock far advanced must also not fire; the fresh
        // interval starts at the current instant.
        scheduler.setPaused(false)
        #expect(scheduler.isPaused == false)
        #expect(scheduler.tick(isPresent: true) == false)
    }
}
