import Foundation
import Testing

@testable import AnearCore

struct CountdownFormatTests {
    @Test func displaysCompactHumanReadableCountdowns() {
        let cases: [(seconds: TimeInterval, expected: String)] = [
            (0, "0s"),
            (-3, "0s"),
            (0.1, "1s"),
            (30, "30s"),
            (59, "59s"),
            (60, "1m"),
            (61, "1m 1s"),
            (90, "1m 30s"),
            (315, "5m 15s"),
            (3600, "1h"),
            (3610, "1h 10s"),
            (4210, "1h 10m 10s"),
            (36 * 3600, "36h"),
        ]

        for (seconds, expected) in cases {
            #expect(
                CountdownFormat.display(seconds: seconds) == expected,
                "\(seconds) seconds should display as \(expected)"
            )
        }
    }
}
