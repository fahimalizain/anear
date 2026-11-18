import AnearCore
import AppKit
import ServiceManagement

// Anear — Dock-less menu-bar accessory (`@main`-style top-level code in
// main.swift). Shows a status item with Pause, Preview, Config…, Start at
// Login, and Quit. A presence-gated sparse scheduler deals the next
// shuffle-bag line every 8–20 minutes of *active* time (both bounds come
// from the JSON config file) and shows the fading pill; it stays silent on
// idle, lock, screensaver, sleep, and secure input. It also stays silent while
// the screen is being captured, unless Hide While Sharing is off.
// Pause is sticky across launches; Start at Login registers the app bundle
// via SMAppService (on by default after first launch). Lines and interval
// live in `~/Library/Application Support/Anear/config.json` (see
// `ConfigStore`).

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
    /// The pause in effect, restored from UserDefaults at launch. This is the
    /// source of truth: the scheduler only mirrors it, so `apply` is the one
    /// path that changes either. Choosing a duration in the Pause submenu,
    /// Resume Now, and the tick's expiry all land here.
    private var pauseState: PauseState
    private let presence = PresenceMonitor()
    /// Capture is a *hold*, not a pause: it freezes the scheduler and leaves
    /// the glyph undimmed, and it never reaches `PauseStore`. Fed by the
    /// monitor's notifications and sampled once per tick.
    private var captureHold = CaptureHold()
    private let captureMonitor = ScreenCaptureMonitor()
    private let captureStore = CaptureSuppressionStore(defaults: .standard)
    private var timer: Timer?
    /// Wired after the status item and menu are created below.
    weak var statusItem: NSStatusItem?
    weak var countdownItem: NSMenuItem?
    weak var pauseItem: NSMenuItem?
    /// The Pause submenu, held instead of an array of its items: `updateTitles`
    /// repaints by walking it, so the items stay owned by the menu that will
    /// show them and no parallel list can drift out of sync.
    weak var pauseSubmenu: NSMenu?
    weak var loginItem: NSMenuItem?
    /// The Hide While Sharing checkbox, painted from `captureStore`.
    weak var suppressItem: NSMenuItem?
    /// Disabled while capture is latched: a click would deal a line onto the
    /// shared screen. A pause does not disable it.
    weak var previewItem: NSMenuItem?
    /// Created on first use, owned for the process lifetime. The window's
    /// closures hold us weakly, so there is no cycle.
    private lazy var configWindow = ConfigWindow(
        fileURL: configStore.fileURL,
        onSave: { [weak self] config in self?.saveConfig(config) },
        onPreview: { [weak self] text, followCursor, holdDuration in
            // The menu item is disabled while captured; this guard is the real
            // check, and it covers the Config window's Preview button too.
            guard let self, !self.captureHold.isCaptured else { return }
            self.overlay.show(
                text: text,
                followCursor: followCursor,
                holdDuration: holdDuration
            )
        }
    )

    override init() {
        config = configStore.load()
        lines = config.lines
        intervalRange.min = config.minIntervalSeconds
        intervalRange.max = config.maxIntervalSeconds
        // Local so the @Sendable closure can capture it before super.init.
        let range = intervalRange
        scheduler = SparseScheduler(
            now: { ProcessInfo.processInfo.systemUptime },
            nextInterval: { Double.random(in: range.min...range.max) }
        )
        pauseState = pauseStore.load(at: Date())
        super.init()
        // Sticky pause: restore the persisted pause state before the first
        // tick, so a relaunch during a pause starts paused. `load` reads an
        // expired timed pause back as running.
        if pauseState.isPaused {
            scheduler.setPaused(true)
        }
        // Sample capture before the first tick, so a relaunch mid-call does not
        // paint a running countdown over a frozen one. A rising edge here
        // dismisses nothing — no pill exists yet — but it latches the hold.
        captureMonitor.onChange = { [weak self] in
            self?.refreshCapture()
            self?.updateTitles()
        }
        captureMonitor.start()
        refreshCapture()
        registerLoginItemOnFirstLaunch()
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    /// One tick per second on the main run loop. Fires a line exactly when
    /// the scheduler's countdown completes and presence says it is safe;
    /// the tick also refreshes the countdown item in the status menu.
    private func startTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.schedulerTick()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func schedulerTick() {
        // Expiry is evaluated at the top of the tick, so a pause whose deadline
        // has just passed is already running by the time the scheduler drains
        // its countdown. Ending a pause this way goes through the same `apply`
        // as Resume Now, which means `setPaused(false)` rolls a fresh 8–20
        // minute interval: an expiry is never immediately followed by a line.
        let now = Date()
        let refreshed = pauseState.refreshed(at: now)
        if refreshed != pauseState {
            apply(refreshed)
        }
        // Capture freezes the scheduler the way idling does — the leftover
        // wait is kept, not discarded — but an explicit pause still wins, and
        // it was just refreshed above. This never pauses the scheduler itself
        // and never writes `PauseStore`: a capture is not a choice the user
        // made.
        refreshCapture()
        let present = CapturePolicy.schedulerIsPresent(
            humanPresent: presence.isPresent,
            captureLatched: captureHold.isCaptured
        )
        let fired = scheduler.tick(isPresent: present)
        updateTitles()
        guard fired, let text = bag.next(from: lines.map(\.text)) else { return }
        overlay.show(
            text: text,
            followCursor: config.followCursor,
            holdDuration: config.holdDuration
        )
    }

    /// Starts the chosen pause from now. Choosing a duration while already
    /// paused *replaces* the pause — a new deadline counted from this instant —
    /// rather than toggling it away, and choosing the option that is already
    /// ticked re-arms it for another full duration. The tag is the item's index
    /// in `PauseDuration.allCases`, which the model declares in menu order;
    /// anything outside that range (a separator's default tag, say) is ignored.
    @objc func pauseForDuration(_ sender: NSMenuItem) {
        guard PauseDuration.allCases.indices.contains(sender.tag) else { return }
        let duration = PauseDuration.allCases[sender.tag]
        apply(PauseState.started(duration, at: Date(), calendar: .current))
    }

    /// Ends a pause early, from the submenu's last entry. Runs through the same
    /// `apply` as expiry, so resume rolls a fresh interval either way.
    @objc func resumeNow(_ sender: Any?) {
        apply(.running)
    }

    /// The one place a pause change lands, in a deliberate order: the model
    /// first, then the scheduler mirror, then the store, then the chrome.
    /// Resume must pass through here so the scheduler rolls its fresh interval
    /// *before* anything repaints — the countdown item reads the scheduler, so
    /// it would otherwise show the wait that resume throws away.
    ///
    /// A pause also closes an already-visible pill: its hold is cut short and
    /// the normal fade starts now, so a line on screen does not outlive the
    /// pause. Resume and expiry arrive here with `.running` and leave the
    /// overlay alone.
    private func apply(_ state: PauseState) {
        pauseState = state
        scheduler.setPaused(state.isPaused)
        pauseStore.save(state)
        if state.isPaused {
            overlay.dismiss()
        }
        updateTitles()
    }

    /// Reflects the pause model in the status tooltip, the dimmed state of the
    /// status button, the Pause item title, the ticked duration and the hidden
    /// Resume Now entry in the Pause submenu, and the top countdown item.
    /// Called on every pause change, once at launch (sticky pause), every tick,
    /// and whenever the menu opens. The button shows the template glyph, never
    /// a title, so the paused state is carried by `appearsDisabled` and the
    /// tooltip instead. While paused the countdown item names the pause and how
    /// much of it is left, rather than the leftover seconds: those are the
    /// discarded wait that resume throws away when it rolls a fresh interval.
    /// This only reads `pauseState` — expiry belongs to the tick, so opening
    /// the menu can never end a pause.
    ///
    /// Capture is named in the tooltip and the countdown item, and never dims
    /// the button: that dim is the pause signal, and a capture is not a pause.
    func updateTitles() {
        let paused = pauseState.isPaused
        statusItem?.button?.appearsDisabled = paused
        if paused {
            statusItem?.button?.toolTip = "Anear · paused"
        } else if captureHold.isCaptured {
            statusItem?.button?.toolTip = "Anear · sharing"
        } else {
            statusItem?.button?.toolTip = "Anear"
        }
        pauseItem?.title = paused ? "Paused" : "Pause"
        // Pause outranks capture, capture outranks the frozen countdown: the
        // leftover seconds must not be shown moving while nothing is moving.
        switch CapturePolicy.menuStatus(
            pause: pauseState,
            captureLatched: captureHold.isCaptured,
            schedulerRemaining: scheduler.remainingSeconds,
            now: Date()
        ) {
        case .pausedIndefinite:
            countdownItem?.title = "Paused"
        case .pausedUntil(let remaining):
            countdownItem?.title = "Paused · \(CountdownFormat.display(seconds: remaining)) left"
        case .captured:
            countdownItem?.title = "Screen captured"
        case .running(let remaining):
            countdownItem?.title = "Next in \(CountdownFormat.display(seconds: remaining))"
        }
        // Exactly one duration is ticked. Tags are indices into
        // `PauseDuration.allCases`, but nothing else in the submenu may be
        // mistaken for a duration: a separator keeps the default tag 0 (which
        // collides with `.fifteenMinutes`) and is skipped by kind, Resume Now
        // is built with an out-of-range tag, and the bounds check catches
        // anything else unexpected — so no non-duration item can be painted.
        let ticked = pauseState.tickedDuration
        for item in pauseSubmenu?.items ?? [] {
            guard !item.isSeparatorItem,
                PauseDuration.allCases.indices.contains(item.tag)
            else { continue }
            item.state = PauseDuration.allCases[item.tag] == ticked ? .on : .off
        }
        // Resume Now and the divider above it are the submenu's last two
        // entries, and they are toggled together: AppKit hides a separator
        // sitting between other separators, not one whose neighbour was hidden
        // here, so the divider's `isHidden` is set explicitly alongside.
        if let tail = pauseSubmenu?.items.suffix(2) {
            for item in tail {
                item.isHidden = !paused
            }
        }
        suppressItem?.state = captureStore.isEnabled() ? .on : .off
        // Preview survives a pause — it is for checking lines, not the cadence
        // — but not a capture: that click would put a line on the shared screen.
        // When both are true capture wins here only; the countdown row above
        // still names the pause.
        previewItem?.isEnabled = !captureHold.isCaptured
    }

    /// Feeds one capture sample into the hold. Only the rising edge acts: it
    /// closes a pill that is already up, because that line is now on a screen
    /// someone else can see.
    private func refreshCapture() {
        let rising = captureHold.observe(
            rawCaptured: captureMonitor.rawIsCaptured(),
            enabled: captureStore.isEnabled(),
            at: Date()
        )
        if rising {
            overlay.dismiss()
        }
    }

    /// Flips Hide While Sharing. Turning it off drops the latch on the spot —
    /// `observe` with `enabled: false` is not a rising edge, so nothing is
    /// dismissed — and the next tick continues the frozen remainder. Turning it
    /// on samples immediately, so a share already in progress dismisses on that
    /// edge instead of waiting for the next tick.
    @objc func toggleSuppressWhileCaptured(_ sender: Any?) {
        captureStore.setEnabled(!captureStore.isEnabled())
        refreshCapture()
        updateTitles()
    }

    @objc func preview(_ sender: Any?) {
        // The disabled menu item is only the hint; this guard is the real
        // check, and the Config window's Preview button is guarded the same
        // way in its own closure.
        guard !captureHold.isCaptured else { return }
        if let text = bag.next(from: lines.map(\.text)) {
            overlay.show(
                text: text,
                followCursor: config.followCursor,
                holdDuration: config.holdDuration
            )
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
    /// Refresh the countdown item and the Start at Login checkbox every time
    /// the menu opens; the countdown can tick under a mouse-hover and the
    /// login status can change out from under us (System Settings, etc.).
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateTitles()
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
// Read-only countdown of the wait until the next line; the 1 Hz tick keeps
// its title fresh. Disabled: it has no action, so it is display only.
let countdownItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
countdownItem.isEnabled = false
menu.addItem(countdownItem)
menuActions.countdownItem = countdownItem
menu.addItem(.separator())
// Pause is a submenu of the five durations, each of which starts that pause
// from now, plus Resume Now while a pause is in effect. The parent carries no
// action: an item with a submenu opens it on click, and an action alongside a
// submenu would be unreachable.
let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
let pauseSubmenu = NSMenu()
// One item per duration, in `PauseDuration.allCases` order — the model
// declares that as menu order. The tag is that index; `pauseForDuration` maps
// it back, and `updateTitles` walks the same submenu to paint checkmarks.
for (index, duration) in PauseDuration.allCases.enumerated() {
    let item = NSMenuItem(
        title: duration.title,
        action: #selector(MenuActions.pauseForDuration(_:)),
        keyEquivalent: ""
    )
    item.target = menuActions
    item.tag = index
    pauseSubmenu.addItem(item)
}
// Resume Now and its divider are built once and only ever shown or hidden, by
// `updateTitles` while a pause is in effect — nothing re-creates them. Its tag
// is set to a value outside the duration indices on purpose: an item's default
// tag is 0, which is `.fifteenMinutes`, and the checkmark pass paints by tag —
// so a non-duration item in this submenu must be pushed out of that range.
pauseSubmenu.addItem(.separator())
let resumeNowItem = NSMenuItem(
    title: "Resume Now",
    action: #selector(MenuActions.resumeNow(_:)),
    keyEquivalent: ""
)
resumeNowItem.target = menuActions
resumeNowItem.tag = -1
pauseSubmenu.addItem(resumeNowItem)
pauseItem.submenu = pauseSubmenu
menu.addItem(pauseItem)
menuActions.pauseItem = pauseItem
menuActions.pauseSubmenu = pauseSubmenu
let previewItem = NSMenuItem(
    title: "Preview",
    action: #selector(MenuActions.preview(_:)),
    keyEquivalent: ""
)
previewItem.target = menuActions
menu.addItem(previewItem)
menuActions.previewItem = previewItem
let configItem = NSMenuItem(
    title: "Config…",
    action: #selector(MenuActions.openConfig(_:)),
    keyEquivalent: ""
)
configItem.target = menuActions
menu.addItem(configItem)
// On by default (`CaptureSuppressionStore` reads anything but an explicit
// false as on), so a first launch already hides on a share. No tag: it is not
// in the Pause submenu, and the checkmark pass there paints by tag.
let suppressItem = NSMenuItem(
    title: "Hide While Sharing",
    action: #selector(MenuActions.toggleSuppressWhileCaptured(_:)),
    keyEquivalent: ""
)
suppressItem.target = menuActions
menu.addItem(suppressItem)
menuActions.suppressItem = suppressItem
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
