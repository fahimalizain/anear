import Testing

@testable import AnearCore

struct OverlayTimingTests {
    @Test func holdDurationIsFourSeconds() {
        #expect(OverlayTiming.holdDuration == 4.0)
    }

    @Test func fadeDurationIsOneAndQuarterSeconds() {
        #expect(OverlayTiming.fadeDuration == 1.25)
    }

    @Test func totalVisibleDurationIsHoldPlusFade() {
        #expect(OverlayTiming.totalVisibleDuration == 5.25)
    }
}
