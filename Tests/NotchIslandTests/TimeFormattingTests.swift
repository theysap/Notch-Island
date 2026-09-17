import Testing

@testable import NotchIsland

@Suite("Time formatting")
struct TimeFormattingTests {
    @Test("Positions under an hour omit the hour")
    func minutesAndSeconds() {
        #expect(TimeFormatting.position(0) == "0:00")
        #expect(TimeFormatting.position(7) == "0:07")
        #expect(TimeFormatting.position(67) == "1:07")
        #expect(TimeFormatting.position(599) == "9:59")
    }

    @Test("Positions of an hour or more include it")
    func hours() {
        #expect(TimeFormatting.position(3600) == "1:00:00")
        #expect(TimeFormatting.position(3742) == "1:02:22")
    }

    @Test("Seconds are truncated, not rounded up")
    func truncatesTowardsZero() {
        // Rounding up would show a track reaching 3:00 while it still reads
        // 2:59 everywhere else.
        #expect(TimeFormatting.position(179.9) == "2:59")
    }

    @Test("Nonsense input does not produce nonsense output")
    func handlesInvalidInput() {
        #expect(TimeFormatting.position(-5) == "0:00")
        #expect(TimeFormatting.position(.infinity) == "0:00")
        #expect(TimeFormatting.position(.nan) == "0:00")
    }

    @Test("Remaining time is signed")
    func remaining() {
        #expect(TimeFormatting.remaining(83) == "-1:23")
        #expect(TimeFormatting.remaining(-1) == "-0:00")
    }
}
