import AppKit
import AnearCore

// Anear — Dock-less menu-bar accessory (`@main`-style top-level code in
// main.swift). Shows a status item with Pause, Preview, and Quit. A
// presence-gated sparse scheduler deals the next shuffle-bag line every
// 8–20 minutes of *active* time and shows the fading pill; it stays silent
// on idle, lock, screensaver, sleep, and secure input. Pause is sticky
// across launches.

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

    override init() {
        lines = store.load()
        super.init()
        // Sticky pause: restore the persisted state before the first tick.
        if pauseStore.load() {
            scheduler.setPaused(true)
        }
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
}

let menuActions = MenuActions()

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "Anear"
menuActions.statusItem = statusItem

let menu = NSMenu()
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
menu.addItem(.separator())
let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.addItem(quitItem)
statusItem.menu = menu

// Sticky pause: reflect the persisted state on launch if it was restored.
menuActions.updateTitles()

app.run()
