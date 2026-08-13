import AnearCore
import AppKit
import ServiceManagement

// Anear — Dock-less menu-bar accessory (`@main`-style top-level code in
// main.swift). Shows a status item with Pause, Preview, Config…, Start at
// Login, and Quit. A presence-gated sparse scheduler deals the next
// shuffle-bag line every 8–20 minutes of *active* time (both bounds come
// from the JSON config file) and shows the fading pill; it stays silent on
// idle, lock, screensaver, sleep, and secure input.
// Pause is sticky across launches; Start at Login registers the app bundle
// via SMAppService (on by default after first launch). Lines and interval
// live in `~/Library/Application Support/Anear/config.json` (see
// `ConfigStore`), with the pre-JSON UserDefaults lines migrating on the
// first load.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no Dock icon

/// The sparse scheduler's interval bounds in seconds. A class (not a value)
/// so the scheduler's `@Sendable` `nextInterval` closure observes the new
/// bounds immediately when the Config window saves; `resetCountdown` then
/// applies them without firing.
private final class IntervalRange: @unchecked Sendable {
    var min: TimeInterval
    var max: TimeInterval

    init(min: TimeInterval, max: TimeInterval) {
        self.min = min
        self.max = max
    }
}

/// Target for status menu actions. Lives for the process lifetime as a
/// top-level `let`, so `#selector` always has a valid target.
final class MenuActions: NSObject {
    let overlay = OverlayController()
    private let configStore = ConfigStore(fileURL: ConfigStore.defaultFileURL())
    private let intervalRange = IntervalRange(min: 8 * 60, max: 20 * 60)
    private let pauseStore = PauseStore(defaults: .standard)
    private var config: AnearConfig
    private var lines: [Line]
    private var bag = ShuffleBag()
    private var scheduler: SparseScheduler
    private let presence = PresenceMonitor()
    private var timer: Timer?
    /// Wired after the status item and menu are created below.
    weak var statusItem: NSStatusItem?
    weak var pauseItem: NSMenuItem?
    weak var loginItem: NSMenuItem?
    /// Created on first use, owned for the process lifetime. The window's
    /// closures hold us weakly, so there is no cycle.
    private lazy var configWindow = ConfigWindow(
        fileURL: configStore.fileURL,
        onSave: { [weak self] config in self?.saveConfig(config) },
        onPreview: { [weak self] text in self?.overlay.show(text: text) }
    )

    override init() {
        // Config comes from the JSON file; the legacy UserDefaults lines
        // only feed the migration until the first Save writes the file.
        config = configStore.load(migratingFrom: .standard)
        lines = config.lines
        intervalRange.min = config.minIntervalSeconds
        intervalRange.max = config.maxIntervalSeconds
        // Local so the @Sendable closure can capture it before super.init.
        let range = intervalRange
        scheduler = SparseScheduler(
            now: { ProcessInfo.processInfo.systemUptime },
            nextInterval: { Double.random(in: range.min...range.max) }
        )
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
            let text = bag.next(from: lines.map(\.text))
        else { return }
        overlay.show(text: text)
    }

    @objc func togglePause(_ sender: Any?) {
        let paused = !scheduler.isPaused
        scheduler.setPaused(paused)
        pauseStore.save(paused)
        updateTitles()
    }

    /// Reflects scheduler state in the status tooltip, the dimmed state of
    /// the status button, and the Pause item title. Called on toggle and
    /// once at launch (sticky pause). The button shows the template glyph,
    /// never a title, so the paused state is carried by `appearsDisabled`
    /// and the tooltip instead.
    func updateTitles() {
        let paused = scheduler.isPaused
        statusItem?.button?.toolTip = paused ? "Anear · paused" : "Anear"
        statusItem?.button?.appearsDisabled = paused
        pauseItem?.title = paused ? "Resume" : "Pause"
    }

    @objc func preview(_ sender: Any?) {
        if let text = bag.next(from: lines.map(\.text)) {
            overlay.show(text: text)
        }
    }

    @objc func openConfig(_ sender: Any?) {
        configWindow.show(config: config)
    }

    /// Save from the Config window: validate, persist the JSON file, then
    /// swap the new config into memory. The interval box updates so the
    /// next countdown rolls from the new range, and `resetCountdown` applies
    /// it immediately without firing. The shuffle bag refills on its next
    /// deal, because `ShuffleBag.next` rebuilds any deck that is not a
    /// subset of the current pool.
    private func saveConfig(_ newConfig: AnearConfig) {
        var validated = newConfig
        validated.validate()
        try? configStore.save(validated)
        config = validated
        lines = validated.lines
        intervalRange.min = validated.minIntervalSeconds
        intervalRange.max = validated.maxIntervalSeconds
        scheduler.resetCountdown()
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

/// The menu-bar glyph: a bar with a near-dot, keyed to black + alpha for
/// template rendering. `Bundle.module` serves the SPM resources under
/// `swift run`; the packaged `.app` falls back to the PNGs that
/// `make-app.sh` copies into `Bundle.main`'s Resources. Both 1x and @2x
/// representations are attached so the icon stays crisp on retina.
private func menuBarTemplateImage() -> NSImage? {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    var found = false
    for bundle in [Bundle.module, Bundle.main] {
        for name in ["MenuBarTemplate@2x", "MenuBarTemplate"] {
            guard let url = bundle.url(forResource: name, withExtension: "png"),
                let representation = NSImage(contentsOf: url)?.representations.first
            else { continue }
            representation.size = NSSize(width: 18, height: 18)
            image.addRepresentation(representation)
            found = true
        }
    }
    return found ? image : nil
}

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let image = menuBarTemplateImage() {
    image.isTemplate = true
    image.size = NSSize(width: 18, height: 18)
    statusItem.button?.image = image
    statusItem.button?.title = ""
} else {
    // Resources missing (unlikely): fall back to the wordmark.
    statusItem.button?.title = "Anear"
}
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
let configItem = NSMenuItem(
    title: "Config…",
    action: #selector(MenuActions.openConfig(_:)),
    keyEquivalent: ""
)
configItem.target = menuActions
menu.addItem(configItem)
let loginItem = NSMenuItem(
    title: "Start at Login",
    action: #selector(MenuActions.toggleLoginItem(_:)),
    keyEquivalent: ""
)
loginItem.target = menuActions
menu.addItem(loginItem)
menuActions.loginItem = loginItem
menu.addItem(.separator())
let quitItem = NSMenuItem(
    title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.addItem(quitItem)
statusItem.menu = menu

// Sticky pause: reflect the persisted state on launch if it was restored.
menuActions.updateTitles()
// Start at Login: reflect the (one-shot) first-launch registration.
menuActions.updateLoginItem()

app.run()
