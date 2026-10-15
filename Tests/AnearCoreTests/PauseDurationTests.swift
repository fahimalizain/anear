import Foundation
import Testing

@testable import AnearCore

/// `PauseDuration` deadline math. Every test injects a fixed calendar, so the
/// host's time zone and DST rules cannot leak into the assertions.
struct PauseDurationTests {
    private func fixedCalendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func instant(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int,
        in calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        )!
    }

    @Test func fixedDurationsAddTheirWallClockSpan() {
        let calendar = fixedCalendar("UTC")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let fifteenMinutes = PauseDuration.fifteenMinutes.deadline(from: now, calendar: calendar)
        let oneHour = PauseDuration.oneHour.deadline(from: now, calendar: calendar)
        let threeHours = PauseDuration.threeHours.deadline(from: now, calendar: calendar)

        #expect(fifteenMinutes == now.addingTimeInterval(900))
        #expect(oneHour == now.addingTimeInterval(3600))
        #expect(threeHours == now.addingTimeInterval(10_800))
    }

    @Test func indefinitelyHasNoDeadline() {
        let calendar = fixedCalendar("UTC")

        #expect(PauseDuration.indefinitely.deadline(from: Date(), calendar: calendar) == nil)
    }

    @Test func todayIsTheNextMidnight() {
        let calendar = fixedCalendar("UTC")
        let afternoon = instant(2026, 5, 14, 13, 0, 0, in: calendar)

        let deadline = PauseDuration.today.deadline(from: afternoon, calendar: calendar)

        #expect(deadline == instant(2026, 5, 15, 0, 0, 0, in: calendar))
    }

    @Test func todayFromTheLastSecondsOfTheDayIsSecondsAway() {
        let calendar = fixedCalendar("UTC")
        let almostMidnight = instant(2026, 5, 14, 23, 59, 45, in: calendar)

        let deadline = PauseDuration.today.deadline(from: almostMidnight, calendar: calendar)

        #expect(deadline?.timeIntervalSince(almostMidnight) == 15)
    }

    @Test func todayUsesCalendarMathNotAFixedDayLength() {
        // 2026-03-08 is the US spring-forward day: it runs from 00:00 EST to
        // 00:00 EDT, only 23 hours. A naive `startOfDay + 86_400` would land
        // at 01:00 on the 9th rather than at midnight.
        let calendar = fixedCalendar("America/New_York")
        let midday = instant(2026, 3, 8, 13, 0, 0, in: calendar)
        let startOfDay = calendar.startOfDay(for: midday)

        let deadline = PauseDuration.today.deadline(from: midday, calendar: calendar)

        #expect(deadline == instant(2026, 3, 9, 0, 0, 0, in: calendar))
        #expect(deadline?.timeIntervalSince(startOfDay) == 82_800)
        #expect(deadline != startOfDay.addingTimeInterval(86_400))
    }

    @Test func rawValuesAreAPersistedWireFormat() {
        // These exact strings go to UserDefaults under `anear.pauseDuration`,
        // and `anear.pauseState` reuses them for `until`. Changing one without
        // a migration silently drops a saved pause.
        #expect(PauseDuration.fifteenMinutes.rawValue == "fifteenMinutes")
        #expect(PauseDuration.oneHour.rawValue == "oneHour")
        #expect(PauseDuration.threeHours.rawValue == "threeHours")
        #expect(PauseDuration.today.rawValue == "today")
        #expect(PauseDuration.indefinitely.rawValue == "indefinitely")

        // Every case must survive a write/read cycle through its raw value.
        for duration in PauseDuration.allCases {
            #expect(PauseDuration(rawValue: duration.rawValue) == duration)
        }
    }

    @Test func titlesAreTheMenuStrings() {
        #expect(PauseDuration.fifteenMinutes.title == "15 Minutes")
        #expect(PauseDuration.oneHour.title == "1 Hour")
        #expect(PauseDuration.threeHours.title == "3 Hours")
        #expect(PauseDuration.today.title == "Today")
        #expect(PauseDuration.indefinitely.title == "Indefinitely")
    }
}
