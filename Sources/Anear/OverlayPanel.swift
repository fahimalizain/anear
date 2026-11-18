import AnearCore
import AppKit
import SwiftUI

/// The pill content: one line of text on a HUD-material capsule. Text wraps
/// up to `OverlayGeometry.maxWidth` instead of running on one endless line.
struct PillView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: OverlayGeometry.maxWidth)
            .background(Capsule().fill(.ultraThinMaterial))
    }
}

/// Borderless, non-activating, click-through panel that hosts the pill.
/// Never becomes key or main and never activates the app.
final class OverlayPanel: NSPanel {
    let hostingView: NSHostingView<PillView>

    init() {
        let hostingView = NSHostingView(rootView: PillView(text: ""))
        self.hostingView = hostingView
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true  // click-through: zero interaction
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .utilityWindow
        contentView = hostingView
        excludeFromCapture()
    }

    /// Best effort, never the gate. Apple documents `.none` as a legacy value
    /// and ScreenCaptureKit often ignores it, so this only helps captures that
    /// still honour the flag; `CaptureHold` is what actually keeps a line off a
    /// shared screen. Re-applied on every show because AppKit can clear it when
    /// a panel is ordered front.
    func excludeFromCapture() {
        sharingType = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
