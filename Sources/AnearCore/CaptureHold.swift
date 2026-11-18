import Foundation

/// Whether the screen is being captured right now — shared, mirrored, or
/// recorded — latched from a boolean probe the app feeds in.
///
/// Capture is a *hold*, deliberately not a pause: while latched it freezes the
/// scheduler the way idling does (see `CapturePolicy.schedulerIsPresent`), so
/// the user gets their leftover wait back when the call ends instead of
/// starting a fresh interval. It is not `PauseState` for the same reason: the
/// user never chose it, so the menu must not claim a pause is in effect.
///
/// The probe can flicker — a screenshot tool is up for a frame or two, a
/// sharing agent drops a sample — so capture latches on the first captured
/// sample while *release* waits `detachDelay` with no captured sample at all.
/// Only the first uncaptured sample starts that wait; the rest leave its
/// deadline alone, or a 1 Hz poll would push the release out forever.
///
/// Pure and clock-free: `now` is injected and nothing here runs a timer.
public struct CaptureHold: Equatable, Sendable {
    /// How long the screen must go uncaptured before the latch releases. Long
    /// enough to ride out the gap between two frames of the same capture,
    /// short enough that a line can land soon after a call ends.
    public static let detachDelay: TimeInterval = 2

    /// True while capture is latched, including a pending detach: the hold
    /// keeps freezing the scheduler until the wait runs out.
    public private(set) var isCaptured: Bool

    /// When a pending detach releases the latch, or `nil` when none is
    /// pending. Private on purpose — the caller only needs the latch, and a
    /// visible deadline would invite it to schedule a second timer against it.
    private var clearAt: Date?

    /// Starts released: no capture until a sample says so.
    public init() {
        self.isCaptured = false
        self.clearAt = nil
    }

    /// Feeds one probe sample in and returns `true` only on the rising edge —
    /// the call that latched the hold — so the caller can react once per
    /// capture rather than once per sample.
    ///
    /// - `enabled == false` drops the latch and any pending detach immediately,
    ///   even for a captured sample: turning the feature off takes effect on
    ///   this tick, and a forced clear is not a rising edge.
    /// - A captured sample latches and cancels a pending detach. It is an edge
    ///   only if the hold was not already latched, so flicker cannot re-fire.
    /// - While latched, the first uncaptured sample starts the detach; the
    ///   latch releases at `now >= clearAt`. Samples before then keep it and
    ///   report nothing.
    public mutating func observe(rawCaptured: Bool, enabled: Bool, at now: Date) -> Bool {
        guard enabled else {
            isCaptured = false
            clearAt = nil
            return false
        }

        if rawCaptured {
            clearAt = nil
            let wasCaptured = isCaptured
            isCaptured = true
            return !wasCaptured
        }

        guard isCaptured else { return false }

        if let clearAt {
            // The boundary is `now >= clearAt`, the same strictness as
            // `PauseState.refreshed`: the deadline instant is already over, so
            // the hold never lingers for one more tick.
            guard now >= clearAt else { return false }
            isCaptured = false
            self.clearAt = nil
            return false
        }

        clearAt = now.addingTimeInterval(Self.detachDelay)
        return false
    }
}

/// What the status menu says while capture and pause both exist. The order is
/// a rule, not a preference: an explicit pause the user started outranks a
/// capture they did not, and both outrank the running countdown, which is
/// frozen while captured and would otherwise promise time that is not passing.
public enum CaptureMenuStatus: Equatable, Sendable {
    case pausedIndefinite
    case pausedUntil(remaining: TimeInterval)
    case captured
    case running(remaining: TimeInterval)
}

/// The glue between the capture hold and everything that reads presence or the
/// menu. Pure, so the AppKit side only has to wire values through.
public enum CapturePolicy {
    /// Capture freezes the scheduler the way idle does: the leftover wait is
    /// kept, not discarded, so a call costs the user neither their turn nor a
    /// backlog. Idle still wins over capture — with nobody at the machine,
    /// there is no point starting a countdown just because the screen is free.
    public static func schedulerIsPresent(humanPresent: Bool, captureLatched: Bool) -> Bool {
        humanPresent && !captureLatched
    }

    /// Which status to show. `pause` is expected to be refreshed at `now`
    /// already: this never expires a pause, so `PauseState.refreshed` stays the
    /// single place that decides when a timed pause is over.
    public static func menuStatus(
        pause: PauseState,
        captureLatched: Bool,
        schedulerRemaining: TimeInterval,
        now: Date
    ) -> CaptureMenuStatus {
        switch pause {
        case .indefinite:
            return .pausedIndefinite
        case .until:
            // Only running and indefinite have no end, and the switch has
            // ruled them out; 0 beats a crash if that ever changes.
            return .pausedUntil(remaining: pause.remaining(at: now) ?? 0)
        case .running:
            // A captured countdown is frozen, so the scheduler's remaining
            // seconds would be a number that is not moving. Say captured.
            return captureLatched ? .captured : .running(remaining: schedulerRemaining)
        }
    }
}
