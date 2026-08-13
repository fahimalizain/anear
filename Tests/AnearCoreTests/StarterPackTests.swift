import Foundation
import Testing

@testable import AnearCore

struct StarterPackTests {
    @Test func countIsEight() {
        #expect(StarterPack.lines.count == 8)
    }

    @Test func textsMatchSpecExactly() {
        let expected = [
            "I can do hard things.",
            "I begin again.",
            "I have enough time.",
            "I am allowed to rest.",
            "I do one thing.",
            "I am here.",
            "I keep going.",
            "I already know what matters.",
        ]
        #expect(StarterPack.lines.map(\.text) == expected)
    }

    @Test func idsAreUnique() {
        #expect(Set(StarterPack.lines.map(\.id)).count == StarterPack.lines.count)
    }

    @Test func everyLineIsFirstPersonAndShort() {
        for line in StarterPack.lines {
            #expect(line.text.hasPrefix("I "))
            #expect(line.text.count < 80)
        }
    }
}
