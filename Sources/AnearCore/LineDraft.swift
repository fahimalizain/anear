import Foundation

/// Parses and renders the Edit Lines editor text: one first-person line per
/// row. Pure text math with no AppKit, so it is unit-testable in AnearCore.
public enum LineDraft {
    /// Splits `text` on newlines, trims whitespace from each line, and drops
    /// empty / whitespace-only lines. Survivors get fresh `Line` ids: the
    /// list is re-saved wholesale on Save, so identity is not preserved
    /// across edits.
    public static func parse(_ text: String) -> [Line] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Line(text: $0) }
    }

    /// Joins `line.text` with `\n` — the round-trip inverse of `parse`.
    /// No trailing newline beyond the last line.
    public static func render(_ lines: [Line]) -> String {
        lines.map(\.text).joined(separator: "\n")
    }
}
