import Testing
@testable import JustEllipsis

@Suite("BrainEngine")
struct BrainEngineTests {

    @Test("Zero entries gives Curious rank")
    func zeroEntries() {
        #expect(BrainEngine.rank(for: 0) == .curious)
    }

    @Test("25 entries is still Curious")
    func boundaryJustBeforeReader() {
        #expect(BrainEngine.rank(for: 25) == .curious)
    }

    @Test("26 entries unlocks Reader")
    func readerUnlock() {
        #expect(BrainEngine.rank(for: 26) == .reader)
    }

    @Test("Rank thresholds are correct")
    func allThresholds() {
        let cases: [(Int, BrainRank)] = [
            (0,    .curious),
            (25,   .curious),
            (26,   .reader),
            (100,  .reader),
            (101,  .thinker),
            (300,  .thinker),
            (301,  .scholar),
            (750,  .scholar),
            (751,  .polymath),
            (2000, .polymath),
            (2001, .luminary),
            (9999, .luminary),
        ]
        for (count, expected) in cases {
            #expect(BrainEngine.rank(for: count) == expected, "Expected \(expected) for \(count)")
        }
    }

    @Test("Progress is 0.0 at rank floor")
    func progressAtFloor() {
        #expect(BrainEngine.progressToNextRank(for: 26) == 0.0)
    }

    @Test("Progress is 1.0 for Luminary (max rank)")
    func progressAtMaxRank() {
        #expect(BrainEngine.progressToNextRank(for: 2001) == 1.0)
        #expect(BrainEngine.progressToNextRank(for: 9999) == 1.0)
    }

    @Test("entriesUntilNextRank returns 0 at max rank")
    func entriesUntilMaxRank() {
        #expect(BrainEngine.entriesUntilNextRank(for: 2001) == 0)
    }

    @Test("entriesUntilNextRank is correct mid-band")
    func entriesUntilMidBand() {
        // Thinker: 101–300 (100 entry band). At 150, need 151 more.
        #expect(BrainEngine.entriesUntilNextRank(for: 150) == 151)
    }
}
