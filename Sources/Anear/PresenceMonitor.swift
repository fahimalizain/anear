import AppKit
import Carbon
import AnearCore

/// Decides whether the human is actually at the machine and it is safe to
/// show a line. `isPresent` is true only when ALL of:
/// - seconds since last input < `SchedulerTiming.idleThreshold`
/// - the screen is not locked
/// - the screensaver is not running
/// - screens are not asleep
/// - secure event input is not enabled (e.g. a password field)
///
/// Idle time is polled on every read with the standard HID idle query
/// (`.combinedSessionState`, any input event — no Accessibility permission).
/// Lock, screensaver, and sleep state are pushed in by the distributed and
/// workspace notifications.
final class PresenceMonitor: NSObject {
    private var locked = false
    private var screensaverRunning = false
    private var screensAsleep = false

    override init() {
        super.init()
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self, selector: #selector(screenLocked(_:)),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil
        )
        distributed.addObserver(
            self, selector: #selector(screenUnlocked(_:)),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil
        )
        distributed.addObserver(
            self, selector: #selector(screensaverStarted(_:)),
            name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil
        )
        distributed.addObserver(
            self, selector: #selector(screensaverStopped(_:)),
            name: NSNotification.Name("com.apple.screensaver.didstop"), object: nil
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(screensSlept(_:)),
            name: NSWorkspace.screensDidSleepNotification, object: nil
        )
        workspace.addObserver(
            self, selector: #selector(screensWoke(_:)),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// True only when the human is plausibly present and it is safe to show.
    var isPresent: Bool {
        // `~0` is `kCGAnyInputEventType`: "time since any input at all".
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
        return idle < SchedulerTiming.idleThreshold
            && !locked
            && !screensaverRunning
            && !screensAsleep
            && !IsSecureEventInputEnabled()
    }

    @objc private func screenLocked(_ note: Notification) { locked = true }
    @objc private func screenUnlocked(_ note: Notification) { locked = false }
    @objc private func screensaverStarted(_ note: Notification) { screensaverRunning = true }
    @objc private func screensaverStopped(_ note: Notification) { screensaverRunning = false }
    @objc private func screensSlept(_ note: Notification) { screensAsleep = true }
    @objc private func screensWoke(_ note: Notification) { screensAsleep = false }
}
