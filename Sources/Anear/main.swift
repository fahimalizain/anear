import AppKit
import AnearCore

// Anear — Dock-less menu-bar accessory (`@main`-style top-level code in
// main.swift). Shows a status item with Preview and Quit; Preview spawns a
// fading pill of text pinned near the cursor, fed by a shuffle bag over the
// user's lines (starter pack until they edit).

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon

/// Target for status menu actions. Lives for the process lifetime as a
/// top-level `let`, so `#selector` always has a valid target.
final class MenuActions: NSObject {
    let overlay = OverlayController()
    private let store = UserDefaultsLineStore(defaults: .standard)
    private var lines: [Line]
    private var bag = ShuffleBag()

    override init() {
        lines = store.load()
        super.init()
    }

    @objc func preview(_ sender: Any?) {
        if let text = bag.next(from: lines.map(\.text)) {
            overlay.show(text: text)
        }
    }
}

let menuActions = MenuActions()

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "Anear"

let menu = NSMenu()
let previewItem = NSMenuItem(
    title: "Preview",
    action: #selector(MenuActions.preview(_:)),
    keyEquivalent: ""
)
previewItem.target = menuActions
menu.addItem(previewItem)
menu.addItem(.separator())
let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.addItem(quitItem)
statusItem.menu = menu

app.run()
