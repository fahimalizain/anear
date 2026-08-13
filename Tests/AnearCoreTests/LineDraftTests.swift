import Foundation
import Testing

@testable import AnearCore

struct LineDraftTests {
    @Test func emptyOrWhitespaceOnlyTextParsesToNoLines() {
        #expect(LineDraft.parse("") == [])
        #expect(LineDraft.parse("   ") == [])
        #expect(LineDraft.parse("\n\n") == [])
        #expect(LineDraft.parse("  \n\t\n ") == [])
    }

    @Test func parseSplitsTrimsAndDropsEmptyLines() {
        let lines = LineDraft.parse("a\n\n  b  \n\t\nc\n")
        #expect(lines.map(\.text) == ["a", "b", "c"])
    }

    @Test func renderThenParsePreservesTexts() {
        let lines = [
            Line(text: "I can do hard things."),
            Line(text: "I begin again."),
            Line(text: "I am here."),
        ]

        let reparsed = LineDraft.parse(LineDraft.render(lines))

        // Texts survive the round trip; ids are freshly minted and may differ.
        #expect(reparsed.map(\.text) == lines.map(\.text))
        #expect(reparsed.map(\.id) != lines.map(\.id))
    }

    @Test func parseThenRenderJoinsWithSingleNewlines() {
        let lines = [Line(text: "x"), Line(text: "y")]
        #expect(LineDraft.render(lines) == "x\ny")
    }

    @Test func parseAssignsFreshIdsOnEveryCall() {
        let first = LineDraft.parse("a\nb")
        let second = LineDraft.parse("a\nb")
        #expect(first.map(\.id) != second.map(\.id))
    }
}
