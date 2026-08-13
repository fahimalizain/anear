import AppKit

// Anear — Dock-less menu-bar accessory (`@main`-style top-level code in
// main.swift). Shows a status item with a Quit menu; the cursor overlay
// panel arrives in a later slice.

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "Anear"

let menu = NSMenu()
let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.addItem(quitItem)
statusItem.menu = menu

app.run()
