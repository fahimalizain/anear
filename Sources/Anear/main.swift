import AppKit

// Anear — Dock-less menu-bar accessory (`@main`-style top-level code in
// main.swift). Shows a status item with Preview and Quit; Preview spawns a
// fading pill of text pinned near the cursor.

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon

/// Target for status menu actions. Lives for the process lifetime as a
/// top-level `let`, so `#selector` always has a valid target.
final class MenuActions: NSObject {
    let overlay = OverlayController()

    @objc func preview(_ sender: Any?) {
        overlay.show(text: "I begin again.")
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
