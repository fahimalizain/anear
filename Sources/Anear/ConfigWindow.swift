import AnearCore
import AppKit
import SwiftUI

/// The Config window: a real titled, closable, resizable window — not a
/// non-activating panel — so the user can actually type. Edits the ambient
/// lines, the 8–20 minute interval, and the follow-cursor toggle, shows the
/// JSON config file path, and persists them on Save. Save also closes the
/// window (a deliberate change from the old Edit Lines window); Preview
/// shows the last non-empty draft line without saving or closing. Reused
/// for the process lifetime: closing it via the red traffic light only
/// hides it.
final class ConfigWindow: NSWindow {
    private let fileURL: URL
    private let onSave: (AnearConfig) -> Void
    private let onPreview: (String, Bool) -> Void
    /// Created on first use, owned for the process lifetime. The window's
    /// closures hold us weakly, so there is no cycle. Lazy so `persist` can
    /// reference `self` to close the window on Save.
    private lazy var model = ConfigModel(
        filePath: fileURL.path,
        fileExists: FileManager.default.fileExists(atPath: fileURL.path),
        onSave: { [weak self] config in self?.persist(config) },
        onPreview: onPreview
    )
    private lazy var hostingView = NSHostingView(rootView: ConfigView(model: model))

    /// - `onSave`: called with the parsed, validated config when the user
    ///   clicks Save. The window closes immediately afterwards.
    /// - `onPreview`: called with the last non-empty line of the draft and
    ///   the draft's follow-cursor toggle when the user clicks Preview, so
    ///   the toggle can be tried before Save. Not called when the draft
    ///   has no lines.
    init(
        fileURL: URL, onSave: @escaping (AnearConfig) -> Void,
        onPreview: @escaping (String, Bool) -> Void
    ) {
        self.fileURL = fileURL
        self.onSave = onSave
        self.onPreview = onPreview
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Config"
        isReleasedWhenClosed = false  // reuse: hide, never release
        contentView = hostingView
        center()
    }

    /// Handles Save: persist, refresh the file-exists state (Save may have
    /// just created the file), then close the window.
    private func persist(_ config: AnearConfig) {
        onSave(config)
        model.fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        orderOut(nil)
    }

    /// Loads `config` into the editor, the minute fields, and the
    /// follow-cursor toggle, then brings the window forward. This is the
    /// one place the app activates itself; the HUD never does.
    func show(config: AnearConfig) {
        model.text = LineDraft.render(config.lines)
        model.minMinutes = String(config.minIntervalMinutes)
        model.maxMinutes = String(config.maxIntervalMinutes)
        model.followCursor = config.followCursor
        model.fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

/// Editor state shared between the window and its SwiftUI content.
final class ConfigModel: ObservableObject {
    @Published var text: String = ""
    @Published var minMinutes: String = ""
    @Published var maxMinutes: String = ""
    /// Whether the pill should follow the pointer while visible; loaded from
    /// the config on show, persisted on Save.
    @Published var followCursor: Bool = false
    /// Whether the config file exists right now; drives the Reveal button
    /// and the "Created on Save." caption.
    @Published var fileExists: Bool
    let filePath: String
    private let onSave: (AnearConfig) -> Void
    private let onPreview: (String, Bool) -> Void

    init(
        filePath: String,
        fileExists: Bool,
        onSave: @escaping (AnearConfig) -> Void,
        onPreview: @escaping (String, Bool) -> Void
    ) {
        self.filePath = filePath
        self.fileExists = fileExists
        self.onSave = onSave
        self.onPreview = onPreview
    }

    /// Parses the draft, the minute fields, and the follow-cursor toggle
    /// into a config and hands it to the caller, which persists and closes
    /// the window. Unparseable minute fields fall back to the defaults
    /// (8/20); `ConfigStore.save` clamps anything invalid.
    func save() {
        let config = AnearConfig(
            lines: LineDraft.parse(text),
            minIntervalMinutes: Int(minMinutes) ?? 8,
            maxIntervalMinutes: Int(maxMinutes) ?? 20,
            followCursor: followCursor
        )
        onSave(config)
    }

    /// Shows the last non-empty line of the current draft — the
    /// selected-ish, most recently meaningful row — with the draft's
    /// follow-cursor toggle, so the toggle can be tried without saving.
    /// No-op with no lines.
    func preview() {
        guard let last = LineDraft.parse(text).last else { return }
        onPreview(last.text, followCursor)
    }

    /// Reveals the config file in Finder. Only meaningful when the file
    /// exists (the button is disabled otherwise).
    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
    }
}

/// The config content: interval bounds, the follow-cursor toggle, the line
/// editor, the config file path, and Preview (left) / Save (right).
struct ConfigView: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            intervalSection
            followCursorSection
            linesSection
            pathSection
            buttonRow
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 420)
    }

    /// “Every [min] to [max] minutes” — the sparse scheduler's interval.
    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Interval")
                .font(.headline)
            HStack(spacing: 6) {
                Text("Every")
                TextField("8", text: $model.minMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                Text("to")
                TextField("20", text: $model.maxMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                Text("minutes")
            }
        }
    }

    /// Whether the pill follows the pointer while visible. The overlay
    /// tracks the mouse only when this is on; the default keeps the pill
    /// pinned where it spawns.
    private var followCursorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Follow cursor", isOn: $model.followCursor)
            Text("Move the pill with the pointer while it is visible.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lines")
                .font(.headline)
            Text("One first-person line per row.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $model.text)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
    }

    /// The absolute config file path, selectable for copying. Shown even
    /// before the file exists (Save creates it).
    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Config file")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.filePath)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Reveal") { model.reveal() }
                    .disabled(!model.fileExists)
            }
            if !model.fileExists {
                Text("Created on Save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var buttonRow: some View {
        HStack {
            Button("Preview") { model.preview() }
            Spacer()
            Button("Save") { model.save() }
        }
    }
}
