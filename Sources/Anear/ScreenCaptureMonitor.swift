import Foundation

/// Watches the window server's "somebody is capturing the screen" flag — the
/// same private one loginwindow consults before drawing "Your screen is being
/// observed" — so a line never lands on a screen that is being shared,
/// mirrored, or recorded.
///
/// Both halves are private API resolved with `dlsym`, so nothing here prompts,
/// asks for Screen Recording or Accessibility, or assumes the symbol exists: an
/// unresolved symbol reads as *not captured*, which keeps the feature inert
/// instead of leaving lines silenced forever. The attach/detach notifications
/// only add an instant edge on top of the 1 Hz sample the scheduler takes.
final class ScreenCaptureMonitor {
    /// Invoked on the main queue when a watcher attaches or detaches.
    var onChange: (() -> Void)?

    /// The probe is a `() -> Bool`, not session state: a sharing app that is
    /// merely open must not count, and the watcher flag flips exactly when a
    /// capture stream starts.
    private typealias IsCapturedProc = @convention(c) () -> Bool
    private typealias NotifyProc =
        @convention(c) (
            UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?
        ) -> Void
    private typealias RegisterNotifyProc =
        @convention(c) (
            NotifyProc, UInt32, UnsafeMutableRawPointer?
        ) -> Int32

    /// Window-server events: a capture watcher attached or detached. Their
    /// numbers matter, not their payload: either one just asks for a fresh
    /// sample.
    private static let watcherAttached: UInt32 = 1502
    private static let watcherDetached: UInt32 = 1503

    /// Resolved once at first use: a `dlsym` per second would be pointless
    /// work, and the libraries cannot unload under a running app.
    private static let isCapturedProc: IsCapturedProc? = {
        for name in ["SLSIsScreenWatcherPresent", "CGSIsScreenWatcherPresent"] {
            guard let symbol = dlsym(ScreenCaptureMonitor.defaultHandle, name) else { continue }
            return unsafeBitCast(symbol, to: IsCapturedProc.self)
        }
        return nil
    }()

    private static let registerNotifyProc: RegisterNotifyProc? = {
        for name in ["SLSRegisterNotifyProc", "CGSRegisterNotifyProc"] {
            guard let symbol = dlsym(ScreenCaptureMonitor.defaultHandle, name) else { continue }
            return unsafeBitCast(symbol, to: RegisterNotifyProc.self)
        }
        return nil
    }()

    /// `RTLD_DEFAULT`: every library already loaded in this process. The
    /// pointer -2 is the documented value and has no Swift spelling.
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)

    /// A C function pointer carries no context, so both events land in this
    /// one-shot closure, which only asks the hub to sample again.
    private static let notifyProc: NotifyProc = { _, _, _, _ in
        CaptureNotifyHub.shared.fireOnMain()
    }

    /// Publishes the handler first, then registers: an event can arrive as
    /// soon as the registration lands, and it must find something to call.
    /// With no register symbol the tick's own sampling is the whole feature.
    func start() {
        CaptureNotifyHub.shared.setHandler(onChange)
        guard let register = Self.registerNotifyProc,
            CaptureNotifyHub.shared.claimRegistration()
        else { return }
        _ = register(Self.notifyProc, Self.watcherAttached, nil)
        _ = register(Self.notifyProc, Self.watcherDetached, nil)
    }

    func rawIsCaptured() -> Bool {
        guard let proc = Self.isCapturedProc else { return false }
        return proc()
    }
}

/// The process-wide slot the C callback funnels into. It holds the handler and
/// the "already registered" flag because the callback gets no context of its
/// own. The lock, not the main actor: the callback arrives on a window-server
/// thread, and only the handler hop is main.
private final class CaptureNotifyHub: @unchecked Sendable {
    static let shared = CaptureNotifyHub()

    private let lock = NSLock()
    private var handler: (() -> Void)?
    private var registered = false

    func setHandler(_ handler: (() -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    /// True once. There is no unregister call, so a second registration would
    /// run the handler twice for every event.
    func claimRegistration() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !registered else { return false }
        registered = true
        return true
    }

    /// Hops to the main queue, then reads the handler there under the lock:
    /// that keeps the non-`Sendable` closure out of this `@Sendable` block.
    func fireOnMain() {
        DispatchQueue.main.async {
            self.lock.lock()
            let handler = self.handler
            self.lock.unlock()
            handler?()
        }
    }
}
