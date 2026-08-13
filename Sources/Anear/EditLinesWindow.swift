import AnearCore
import AppKit
import SwiftUI

/// The Edit Lines window: a real titled, closable, resizable window — not a
/// non-activating panel — so the user can actually type. Reused for the
/// process lifetime: closing it via the red traffic light only hides it,
/// and Save is the only thing that persists (no autosave on close).
final class EditLinesWindow: NSWindow {
    private let model: EditLinesModel
    private let hostingView: NSHostingView<EditLinesView>

    /// - `onSave`: called with the freshly parsed lines when the user clicks
    ///   Save. The window stays open.
    /// - `onPreview`: called with the last non-empty line of the draft when
    ///   the user clicks Preview. Not called when the draft has no lines.
    init(onSave: @escaping ([Line]) -> Void, onPreview: @escaping (String) -> Void) {
        let model = EditLinesModel(onSave: onSave, onPreview: onPreview)
        self.model = model
        let hostingView = NSHostingView(rootView: EditLinesView(model: model))
        self.hostingView = hostingView
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Edit Lines"
        isReleasedWhenClosed = false  // reuse: hide, never release
        contentView = hostingView
        center()
    }

    /// Loads `lines` into the editor and brings the window forward. This is
    /// the one place the app activates itself; the HUD never does.
    func show(lines: [Line]) {
        model.text = LineDraft.render(lines)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

/// Editor state shared between the window and its SwiftUI content.
final class EditLinesModel: ObservableObject {
    @Published var text: String = ""
    private let onSave: ([Line]) -> Void
    private let onPreview: (String) -> Void

    init(onSave: @escaping ([Line]) -> Void, onPreview: @escaping (String) -> Void) {
        self.onSave = onSave
        self.onPreview = onPreview
    }

    /// Parses the draft and hands the fresh lines to the caller.
    func save() {
        onSave(LineDraft.parse(text))
    }

    /// Shows the last non-empty line of the current draft — the
    /// selected-ish, most recently meaningful row. No-op with no lines.
    func preview() {
        guard let last = LineDraft.parse(text).last else { return }
        onPreview(last.text)
    }
}

/// The editor content: a caption, a plain text editor (one first-person line
/// per row), and Preview (left) / Save (right).
struct EditLinesView: View {
    @ObservedObject var model: EditLinesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One first-person line per row.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $model.text)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            HStack {
                Button("Preview") { model.preview() }
                Spacer()
                Button("Save") { model.save() }
            }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 320)
    }
}
