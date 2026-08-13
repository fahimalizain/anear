import Testing
@testable import AnearCore

struct ShuffleBagTests {
    @Test func emptyOrWhitespacePoolDealsNil() {
        var bag = ShuffleBag(shuffle: { $0 })
        #expect(bag.next(from: []) == nil)
        #expect(bag.next(from: ["", "   ", "\t", " \n "]) == nil)
        #expect(bag.next(from: ["  ", "", " "]) == nil)
    }

    @Test func whitespaceAroundLinesIsTrimmed() {
        var bag = ShuffleBag(shuffle: { $0 })
        #expect(bag.next(from: ["  hi  ", "\t there "]) == "hi")
        #expect(bag.next(from: ["  hi  ", "\t there "]) == "there")
    }

    @Test func singleLinePoolAlwaysDealsThatLine() {
        var bag = ShuffleBag()
        for _ in 0..<3 {
            #expect(bag.next(from: ["only line"]) == "only line")
        }
    }

    @Test func identityShuffleDealsPoolInOrderAndRestartsCycles() {
        let pool = ["alpha", "bravo", "charlie"]
        var bag = ShuffleBag(shuffle: { $0 })

        // One full cycle: a permutation of the pool (order preserved here).
        var firstCycle: [String] = []
        for _ in 0..<pool.count {
            firstCycle.append(bag.next(from: pool)!)
        }
        #expect(firstCycle == pool)

        // The next deal starts a new cycle of the same permutation.
        var secondCycle: [String] = []
        for _ in 0..<pool.count {
            secondCycle.append(bag.next(from: pool)!)
        }
        #expect(secondCycle == pool)
    }

    @Test func noImmediateRepeatAcrossRefill() {
        // Cycle 1 deals [a, b, c]; the refill would open with "c" — the line
        // that just ended the cycle — so the bag must swap it out of position
        // 0 before dealing.
        var shuffles = [
            ["a", "b", "c"],
            ["c", "a", "b"],
        ]
        var bag = ShuffleBag(shuffle: { _ in shuffles.removeFirst() })
        let pool = ["a", "b", "c"]

        #expect(bag.next(from: pool) == "a")
        #expect(bag.next(from: pool) == "b")
        #expect(bag.next(from: pool) == "c") // last of cycle 1

        // First deal of cycle 2 must differ from "c" (swap rule), and the
        // rest of the cycle is still a permutation of the pool.
        #expect(bag.next(from: pool) == "a")
        #expect(bag.next(from: pool) == "c")
        #expect(bag.next(from: pool) == "b")
    }

    @Test func reverseShuffleDealsReversedOrder() {
        let pool = ["a", "b", "c"]
        var bag = ShuffleBag(shuffle: { Array($0.reversed()) })

        var dealt: [String] = []
        for _ in 0..<pool.count {
            dealt.append(bag.next(from: pool)!)
        }

        #expect(dealt == ["c", "b", "a"])
    }

    @Test func editedPoolRefillsDeck() {
        var bag = ShuffleBag(shuffle: { $0 })
        #expect(bag.next(from: ["a", "b", "c"]) == "a")

        // The remaining deck [b, c] is not a subset of the new pool, so the
        // next deal refills from the edited pool instead of continuing.
        #expect(bag.next(from: ["x", "y", "z"]) == "x")
    }
}
