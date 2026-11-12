import Foundation

/// Picks the daily passage so that every tradition gets an equal share of days:
/// day N goes to pool (N mod poolCount), then walks through that pool on successive turns.
enum DailyRotation {
    static func dayNumber(for date: Date) -> Int {
        Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: date) ?? 0
    }

    /// Returns (pool index, offset within pool), or nil if every pool is empty.
    static func pick(day: Int, poolSizes: [Int]) -> (pool: Int, offset: Int)? {
        let pools = poolSizes.enumerated().filter { $0.element > 0 }
        guard !pools.isEmpty else { return nil }
        let chosen = pools[day % pools.count]
        return (chosen.offset, (day / pools.count) % chosen.element)
    }
}
