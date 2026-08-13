import AnearCore
import AppKit
import QuartzCore

/// Owns the overlay panel and its show/hold/fade lifecycle. The panel is
/// created once and reused; each `show` pins the pill at the current cursor
/// location and restarts the hold and fade.
final class OverlayController {
    private let panel: OverlayPanel
    private var fadeWork: DispatchWorkItem?
    /// Bumped on every `show` so stale fade/hide work can never touch a
    /// freshly shown pill.
    private var generation = UUID()

    init() {
        panel = OverlayPanel()
    }

    /// Pins a pill of `text` near the current cursor location, holds it, then
    /// fades it out. A call while the pill is visible restarts the cycle.
    func show(text: String) {
        // Restart the cycle: drop pending fade work and snap back to full
        // opacity (also cuts any in-flight fade animation).
        fadeWork?.cancel()
        fadeWork = nil
        generation = UUID()
        panel.alphaValue = 1

        // Size to the pill content, capped at the placement design width.
        panel.hostingView.rootView = PillView(text: text)
        panel.hostingView.layoutSubtreeIfNeeded()
        var size = panel.hostingView.fittingSize
        size.width = min(size.width, OverlayGeometry.maxWidth)
        panel.setContentSize(size)

        // Pin near the cursor on the screen under it, using that screen's
        // visible frame (menu bar / Dock excluded), never its full frame.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let placement = OverlayGeometry.place(
            cursor: mouse,
            panelSize: panel.frame.size,
            visibleFrame: visibleFrame
        )
        panel.setFrameOrigin(placement.origin)  // no animation: pinned at spawn

        panel.orderFrontRegardless()

        // Hold, then fade, then hide. Preview again cancels this work item.
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut(token: token)
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + OverlayTiming.holdDuration,
            execute: work
        )
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
        }
    }
}
