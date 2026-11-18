import Foundation
import Testing

@testable import AnearCore

/// `CaptureHold` as a pure value — latch on a captured sample, release only
/// after `detachDelay` seconds of uncaptured ones, and let the caller switch
/// the whole thing off on the spot — plus the `CapturePolicy` rules that sit on
/// top of it. Every test injects `now`, mirroring `PauseStateTests`.
///
/// The edge flags are bound to a `let` before `#expect`: the macro decomposes a
/// call into a closure over an immutable copy, which a `mutating` method cannot
/// take.
struct CaptureHoldTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let delay = CaptureHold.detachDelay

    /// An instant `seconds` after the base time, so every assertion spells out
    /// the gap between samples instead of an absolute date.
    private func after(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
    }

    /// A hold that has already seen one captured sample, so the release tests
    /// start latched instead of replaying the rising edge.
    private func latchedHold() -> CaptureHold {
        var hold = CaptureHold()
        _ = hold.observe(rawCaptured: true, enabled: true, at: now)
        return hold
    }

    // MARK: - CaptureHold

    @Test func uncapturedSamplesWhileReleasedStayReleased() {
        var hold = CaptureHold()

        let idle = hold.observe(rawCaptured: false, enabled: true, at: after(0))
        let stillIdle = hold.observe(rawCaptured: false, enabled: true, at: after(60))

        #expect(idle == false)
        #expect(stillIdle == false)
        #expect(hold.isCaptured == false)
    }

    @Test func firstCapturedSampleLatchesAndReportsARisingEdge() {
        var hold = CaptureHold()

        let edge = hold.observe(rawCaptured: true, enabled: true, at: after(0))

        #expect(edge)
        #expect(hold.isCaptured)
    }

    @Test func capturedWhileLatchedIsNotARisingEdge() {
        var hold = latchedHold()

        let edge = hold.observe(rawCaptured: true, enabled: true, at: after(1))

        #expect(edge == false)
        #expect(hold.isCaptured)
    }

    @Test func uncapturedSampleBeforeTheDelayKeepsTheLatch() {
        var hold = latchedHold()

        let started = hold.observe(rawCaptured: false, enabled: true, at: after(0))
        // One tick short of the delay: still latched, and no edge.
        let early = hold.observe(rawCaptured: false, enabled: true, at: after(delay - 0.001))

        #expect(started == false)
        #expect(early == false)
        #expect(hold.isCaptured)
    }

    @Test func releasesExactlyAtTheDetachDelay() {
        var hold = latchedHold()
        let started = hold.observe(rawCaptured: false, enabled: true, at: after(0))

        // The boundary is `now >= clearAt`, so the deadline instant itself is
        // already released rather than lingering for one more tick.
        let released = hold.observe(rawCaptured: false, enabled: true, at: after(delay))

        #expect(started == false)
        #expect(released == false)
        #expect(hold.isCaptured == false)
    }

    @Test func laterUncapturedSamplesDoNotPushTheDeadline() {
        var hold = latchedHold()

        // The 0s sample starts a clock that clears at 2s. A 1 Hz poll keeps
        // sampling: if each sample restarted the clock, the hold would never
        // release and lines would never come back.
        let started = hold.observe(rawCaptured: false, enabled: true, at: after(0))
        let polled = hold.observe(rawCaptured: false, enabled: true, at: after(1.9))
        #expect(started == false)
        #expect(polled == false)
        #expect(hold.isCaptured)

        let released = hold.observe(rawCaptured: false, enabled: true, at: after(2))

        #expect(released == false)
        #expect(hold.isCaptured == false)
    }

    @Test func capturedSampleCancelsAPendingDetach() {
        var hold = latchedHold()
        let started = hold.observe(rawCaptured: false, enabled: true, at: after(0))
        #expect(started == false)

        // Capture resumes a second in: the hold stays latched throughout, so
        // this is not an edge.
        let resumed = hold.observe(rawCaptured: true, enabled: true, at: after(1))
        #expect(resumed == false)
        #expect(hold.isCaptured)

        // The cancelled wait would have ended at 2s; the latch outlives it.
        let pastTheOldDeadline = hold.observe(rawCaptured: true, enabled: true, at: after(2.5))
        #expect(pastTheOldDeadline == false)
        #expect(hold.isCaptured)

        // The first uncaptured sample after that starts a whole new wait from
        // itself, and only that wait releases.
        let restarted = hold.observe(rawCaptured: false, enabled: true, at: after(3))
        let stillHeld = hold.observe(rawCaptured: false, enabled: true, at: after(5 - 0.001))
        #expect(restarted == false)
        #expect(stillHeld == false)
        #expect(hold.isCaptured)

        let released = hold.observe(rawCaptured: false, enabled: true, at: after(5))
        #expect(released == false)
        #expect(hold.isCaptured == false)
    }

    @Test func disablingClearsTheLatchImmediately() {
        var hold = latchedHold()

        // The sample itself still reports capture, but the feature is off:
        // turning it off is not allowed to wait for a detach, and the forced
        // clear is not a rising edge.
        let edge = hold.observe(rawCaptured: true, enabled: false, at: after(0))

        #expect(edge == false)
        #expect(hold.isCaptured == false)
    }

    @Test func disabledStaysReleasedForACapturedSample() {
        var hold = CaptureHold()

        let edge = hold.observe(rawCaptured: true, enabled: false, at: after(0))

        #expect(edge == false)
        #expect(hold.isCaptured == false)
    }

    @Test func reEnablingRaisesTheLatchAgain() {
        var hold = latchedHold()
        // Leave a detach pending before switching the feature off, so this
        // also proves the disable forgot it: the next captured sample is a
        // fresh rising edge, not a leftover latch.
        _ = hold.observe(rawCaptured: false, enabled: true, at: after(0))
        let cleared = hold.observe(rawCaptured: true, enabled: false, at: after(0.5))

        let edge = hold.observe(rawCaptured: true, enabled: true, at: after(1))

        #expect(cleared == false)
        #expect(edge)
        #expect(hold.isCaptured)
    }

    // MARK: - CapturePolicy

    @Test func schedulerIsPresentOnlyWhenTheHumanIsPresentAndNotCaptured() {
        #expect(
            CapturePolicy.schedulerIsPresent(humanPresent: true, captureLatched: false)
        )
        #expect(
            CapturePolicy.schedulerIsPresent(humanPresent: true, captureLatched: true) == false
        )
        #expect(
            CapturePolicy.schedulerIsPresent(humanPresent: false, captureLatched: false) == false
        )
        #expect(
            CapturePolicy.schedulerIsPresent(humanPresent: false, captureLatched: true) == false
        )
    }

    @Test func indefinitePauseBeatsCapture() {
        let status = CapturePolicy.menuStatus(
            pause: .indefinite,
            captureLatched: true,
            schedulerRemaining: 42,
            now: now
        )

        #expect(status == .pausedIndefinite)
    }

    @Test func timedPauseBeatsCaptureAndKeepsItsRemaining() {
        let pause = PauseState.until(.oneHour, deadline: after(3600))

        let whileCaptured = CapturePolicy.menuStatus(
            pause: pause,
            captureLatched: true,
            schedulerRemaining: 42,
            now: now
        )
        #expect(whileCaptured == .pausedUntil(remaining: 3600))

        // Capture does not change the pause's remaining time, and the
        // scheduler's number is ignored while anything is paused.
        let whileReleased = CapturePolicy.menuStatus(
            pause: pause,
            captureLatched: false,
            schedulerRemaining: 42,
            now: now
        )
        #expect(whileReleased == .pausedUntil(remaining: 3600))
    }

    @Test func timedPauseRemainingCountsFromTheInjectedNow() {
        let pause = PauseState.until(.oneHour, deadline: after(3600))

        let status = CapturePolicy.menuStatus(
            pause: pause,
            captureLatched: false,
            schedulerRemaining: 42,
            now: after(600)
        )

        #expect(status == .pausedUntil(remaining: 3000))
    }

    @Test func runningWhileCapturedIsCaptured() {
        // A captured countdown is frozen, so the scheduler's remaining seconds
        // would be time that is not passing; the menu says captured instead.
        let status = CapturePolicy.menuStatus(
            pause: .running,
            captureLatched: true,
            schedulerRemaining: 42,
            now: now
        )

        #expect(status == .captured)
    }

    @Test func runningWhileReleasedShowsTheSchedulerRemaining() {
        let status = CapturePolicy.menuStatus(
            pause: .running,
            captureLatched: false,
            schedulerRemaining: 42,
            now: now
        )

        #expect(status == .running(remaining: 42))
    }
}
