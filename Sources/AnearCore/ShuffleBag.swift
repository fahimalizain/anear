import Foundation

/// Deals lines from a pool shuffle-bag style: a full cycle of `pool.count`
/// deals is exactly a permutation of the pool (no dupes, no missing), and —
/// for pools of two or more — a refill never opens with the line that ended
/// the previous cycle.
public struct ShuffleBag: Sendable {
    /// Not-yet-dealt lines, in deal order.
    private var deck: [String] = []
    /// The last line dealt; nil before the first deal.
    private var lastDealt: String?
    /// Fills the deck from a pool. Injected so tests are deterministic.
    private let shuffle: @Sendable ([String]) -> [String]

    public init(shuffle: @escaping @Sendable ([String]) -> [String] = { $0.shuffled() }) {
        self.shuffle = shuffle
    }

    /// Trims whitespace and drops empty lines, then deals the next line.
    /// Returns nil when the cleaned pool is empty.
    public mutating func next(from lines: [String]) -> String? {
        let pool = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !pool.isEmpty else { return nil }

        // The pool may have been edited since the deck was filled; a deck
        // with any value no longer in the pool must be rebuilt.
        if !Set(deck).isSubset(of: pool) {
            refill(from: pool)
        }
        if deck.isEmpty {
            refill(from: pool)
        }

        let line = deck.removeFirst()
        lastDealt = line
        return line
    }

    /// Fills the deck with a fresh shuffle of `pool`, guarding against an
    /// immediate repeat of the last dealt line when the pool has two or more.
    private mutating func refill(from pool: [String]) {
        deck = shuffle(pool)
        // deck is a permutation of pool, so when pool.count >= 2 and the deck
        // opens with lastDealt, some later index holds a different line —
        // swap it to the front to break the immediate repeat.
        if pool.count >= 2,
           let lastDealt,
           deck.first == lastDealt,
           let swapIndex = deck.firstIndex(where: { $0 != lastDealt }) {
            deck.swapAt(0, swapIndex)
        }
    }
}
