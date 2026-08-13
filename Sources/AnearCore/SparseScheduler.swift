import Foundation

/// Pure, AppKit-free scheduler that fires a line after a sparse random
/// interval of *present* time: 8–20 minutes by default, so lines land
/// irregularly and only while the human is at the machine.
///
/// The clock and the interval generator are injected so tests are
/// deterministic; no timers run inside.
///
/// Idle and pause are deliberately different:
/// - Idle (`tick(isPresent: false)`) *freezes* the countdown — returning
///   present resumes the leftover wait, so a long absence never causes a
///   backlog of fires.
/// - Pause (`setPaused(true)`) *discards* the countdown — the remaining
///   time is irrelevant until `setPaused(false)` rolls a fresh interval
///   that starts from now.
public struct SparseScheduler: Sendable {
    private let now: @Sendable () -> TimeInterval
    private let nextInterval: @Sendable () -> TimeInterval

    /// True while the scheduler is paused. Paused schedulers never fire.
    public private(set) var isPaused: Bool
    /// Seconds until the next fire, while present and unpaused.
    private var remaining: TimeInterval
    /// The last `now` observed (init, unpause, or a tick).
    private var lastTick: TimeInterval

    /// - Parameters:
    ///   - now: Injected clock in seconds (e.g. `systemUptime`).
    ///   - nextInterval: Rolls the interval for the next fire. Defaults to
    ///     `Double.random(in: SchedulerTiming.minInterval...maxInterval)`.
    public init(
        now: @escaping @Sendable () -> TimeInterval,
        nextInterval: @escaping @Sendable () -> TimeInterval = {
            Double.random(in: SchedulerTiming.minInterval...SchedulerTiming.maxInterval)
        }
    ) {
        self.now = now
        self.nextInterval = nextInterval
        self.isPaused = false
        self.remaining = nextInterval()
        self.lastTick = now()
    }

    /// Pause discards the current countdown. Resume rolls a fresh interval
    /// and resets the clock reference to now, so it does not fire
    /// immediately. Never fires by itself.
    public mutating func setPaused(_ paused: Bool) {
        isPaused = paused
        guard !paused else { return }
        remaining = nextInterval()
        lastTick = now()
    }

    /// Advance the scheduler one step using the injected clock.
    ///
    /// - `isPresent == false` freezes the remaining countdown: no drain, no
    ///   fire. Returning to present continues the leftover wait — no backlog.
    /// - While paused, only the last-seen `now` is updated.
    /// - Returns `true` exactly when a line should be shown. At most one
    ///   fire per tick.
    public mutating func tick(isPresent: Bool) -> Bool {
        let current = now()
        defer { lastTick = current }

        if isPaused || !isPresent {
            return false
        }

        remaining -= current - lastTick
        guard remaining <= 0 else { return false }
        remaining = nextInterval()
        return true
    }
}
