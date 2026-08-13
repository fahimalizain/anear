import AppKit
import AnearCore
import ServiceManagement

// Anear — Dock-less menu-bar accessory (`@main`-style top-level code in
// main.swift). Shows a status item with Pause, Preview, Edit Lines…, Start
// at Login, and Quit. A presence-gated sparse scheduler deals the next
// shuffle-bag line every 8–20 minutes of *active* time and shows the fading
// pill; it stays silent on idle, lock, screensaver, sleep, and secure input.
// Pause is sticky across launches; Start at Login registers the app bundle
// via SMAppService (on by default after first launch).

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon

/// Target for status menu actions. Lives for the process lifetime as a
/// top-level `let`, so `#selector` always has a valid target.
final class MenuActions: NSObject {
    let overlay = OverlayController()
    private let store = UserDefaultsLineStore(defaults: .standard)
    private let pauseStore = PauseStore(defaults: .standard)
    private var lines: [Line]
    private var bag = ShuffleBag()
    private var scheduler = SparseScheduler(
        now: { ProcessInfo.processInfo.systemUptime }
    )
    private let presence = PresenceMonitor()
    private var timer: Timer?
    /// Wired after the status item and menu are created below.
    weak var statusItem: NSStatusItem?
    weak var pauseItem: NSMenuItem?
    weak var loginItem: NSMenuItem?
    /// Created on first use, owned for the process lifetime. The window's
    /// closures hold us weakly, so there is no cycle.
    private lazy var editWindow = EditLinesWindow(
        onSave: { [weak self] lines in self?.saveLines(lines) },
        onPreview: { [weak self] text in self?.overlay.show(text: text) }
    )

    override init() {
        lines = store.load()
        super.init()
        // Sticky pause: restore the persisted state before the first tick.
        if pauseStore.load() {
            scheduler.setPaused(true)
        }
        registerLoginItemOnFirstLaunch()
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    /// One tick per second on the main run loop. Fires a line exactly when
    /// the scheduler's countdown completes and presence says it is safe.
    private func startTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.schedulerTick()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func schedulerTick() {
        guard scheduler.tick(isPresent: presence.isPresent),
              let text = bag.next(from: lines.map(\.text)) else { return }
        overlay.show(text: text)
    }

    @objc func togglePause(_ sender: Any?) {
        let paused = !scheduler.isPaused
        scheduler.setPaused(paused)
        pauseStore.save(paused)
        updateTitles()
    }

    /// Reflects scheduler state in the status title and the Pause item
    /// title. Called on toggle and once at launch (sticky pause).
    func updateTitles() {
        let paused = scheduler.isPaused
        statusItem?.button?.title = paused ? "Anear · paused" : "Anear"
        pauseItem?.title = paused ? "Resume" : "Pause"
    }

    @objc func preview(_ sender: Any?) {
        if let text = bag.next(from: lines.map(\.text)) {
            overlay.show(text: text)
        }
    }

    @objc func editLines(_ sender: Any?) {
        editWindow.show(lines: lines)
    }

    /// Save from the editor: persist the new list, then swap it into memory.
    /// The shuffle bag refills on its next deal, because `ShuffleBag.next`
    /// rebuilds any deck that is not a subset of the current pool.
    private func saveLines(_ newLines: [Line]) {
        store.save(newLines)
        lines = newLines
    }

    /// Registers the app as a login item exactly once, on first launch, so
    /// Start at Login is on by default. Deliberately one-shot: even a failed
    /// `register()` sets the flag, so we never retry-spam. Only a real
    /// `.app` bundle may consume the flag — a bare executable (`swift run`)
    /// must not, or it would permanently disable the default for the app.
    private func registerLoginItemOnFirstLaunch() {
        let flagKey = "anear.didSetLoginItem"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    @objc func toggleLoginItem(_ sender: Any?) {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        updateLoginItem()
    }

    /// Reflects the real login-item status in the Start at Login checkbox.
    /// Called on toggle, at launch, and whenever the menu opens.
    func updateLoginItem() {
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

extension MenuActions: NSMenuDelegate {
    /// Refresh the Start at Login checkbox every time the menu opens; the
    /// status can change out from under us (System Settings, etc.).
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateLoginItem()
    }
}

let menuActions = MenuActions()

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "Anear"
menuActions.statusItem = statusItem

let menu = NSMenu()
menu.delegate = menuActions
let pauseItem = NSMenuItem(
    title: "Pause",
    action: #selector(MenuActions.togglePause(_:)),
    keyEquivalent: ""
)
pauseItem.target = menuActions
menu.addItem(pauseItem)
menuActions.pauseItem = pauseItem
let previewItem = NSMenuItem(
    title: "Preview",
    action: #selector(MenuActions.preview(_:)),
    keyEquivalent: ""
)
previewItem.target = menuActions
menu.addItem(previewItem)
let editItem = NSMenuItem(
    title: "Edit Lines…",
    action: #selector(MenuActions.editLines(_:)),
    keyEquivalent: ""
)
editItem.target = menuActions
menu.addItem(editItem)
let loginItem = NSMenuItem(
    title: "Start at Login",
    action: #selector(MenuActions.toggleLoginItem(_:)),
    keyEquivalent: ""
)
loginItem.target = menuActions
menu.addItem(loginItem)
menuActions.loginItem = loginItem
menu.addItem(.separator())
let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.addItem(quitItem)
statusItem.menu = menu

// Sticky pause: reflect the persisted state on launch if it was restored.
menuActions.updateTitles()
// Start at Login: reflect the (one-shot) first-launch registration.
menuActions.updateLoginItem()

app.run()
