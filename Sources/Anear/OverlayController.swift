import AnearCore
import AppKit
import QuartzCore

/// Owns the overlay panel and its show/hold/fade lifecycle. The panel is
/// created once and reused; each `show` pins the pill at the current cursor
/// location — or, with `followCursor`, tracks the pointer for the pill's
/// whole visible life — and restarts the hold and fade. The hold is passed
/// per call (defaulting to `OverlayTiming.holdDuration`); the fade is always
/// the `OverlayTiming.fadeDuration` product constant.
final class OverlayController {
    private let panel: OverlayPanel
    private var fadeWork: DispatchWorkItem?
    /// Bumped on every `show` so stale fade/hide work can never touch a
    /// freshly shown pill.
    private var generation = UUID()
    /// Cursor-tracking event monitors, installed only while `followCursor`
    /// is on. Both a local and a global monitor: the local one sees moves
    /// over this app's own windows (the Config window activates the app),
    /// the global one sees moves over every other app.
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init() {
        panel = OverlayPanel()
    }

    deinit {
        stopTracking()
    }

    /// Shows a pill of `text` near the current cursor location, holds it for
    /// `holdDuration`, then fades it out. With `followCursor` the pill
    /// follows the pointer for its whole visible life (local monitor for
    /// this app's windows, global for everyone else); without it, the pill
    /// stays pinned where it spawned. A call while the pill is visible
    /// restarts the cycle.
    func show(
        text: String,
        followCursor: Bool = false,
        holdDuration: TimeInterval = OverlayTiming.holdDuration
    ) {
        // Restart the cycle: drop pending fade work and snap back to full
        // opacity (also cuts any in-flight fade animation). Stop tracking
        // too, before optionally restarting it, so a restart can never
        // leak a monitor.
        fadeWork?.cancel()
        fadeWork = nil
        generation = UUID()
        stopTracking()
        panel.alphaValue = 1

        // Size to the pill content, capped at the placement design width.
        panel.hostingView.rootView = PillView(text: text)
        panel.hostingView.layoutSubtreeIfNeeded()
        var size = panel.hostingView.fittingSize
        size.width = min(size.width, OverlayGeometry.maxWidth)
        panel.setContentSize(size)

        pinToCursor()
        panel.orderFrontRegardless()

        // Follow the pointer for the pill's whole visible life if asked.
        if followCursor {
            startTracking()
        }

        // Hold, then fade, then hide. Preview again cancels this work item.
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut(token: token)
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + holdDuration,
            execute: work
        )
    }

    /// Places the panel next to the current cursor position, using the
    /// screen under it and that screen's visible frame (menu bar / Dock
    /// excluded), never its full frame. Called at spawn and, while
    /// tracking, on every mouse move.
    private func pinToCursor() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let placement = OverlayGeometry.place(
            cursor: mouse,
            panelSize: panel.frame.size,
            visibleFrame: visibleFrame
        )
        panel.setFrameOrigin(placement.origin)  // no animation: snap, never animate
    }

    /// Installs the local and global cursor-tracking monitors. The local
    /// monitor only sees events this app handles, so the global one is
    /// needed too: the pill must follow the pointer even while the user
    /// works in another app.
    private func startTracking() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.pinToCursor()
            return event  // unchanged: the app must still receive it
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.pinToCursor()
        }
    }

    /// Removes the tracking monitors. Idempotent, so it is safe to call
    /// whether or not tracking is active.
    private func stopTracking() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func fadeOut(token: UUID) {
        guard token == generation else { return }
        NSAnimationContext.runAnimationGroup { [weak self] context in
            context.duration = OverlayTiming.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self?.panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, token == self.generation else { return }
            self.panel.orderOut(nil)
            // Tracking ends with visibility: keep following through the
            // fade, and only stop once the pill is actually gone.
            self.stopTracking()
        }
    }
}
