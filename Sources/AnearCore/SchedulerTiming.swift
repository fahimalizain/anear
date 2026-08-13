import Foundation

/// Timing constants for the presence-gated sparse scheduler: how often lines
/// may appear while the human is present, and how long without input counts
/// as away.
public enum SchedulerTiming {
    /// Shortest gap between two lines while present.
    public static let minInterval: TimeInterval = 8 * 60
    /// Longest gap between two lines while present.
    public static let maxInterval: TimeInterval = 20 * 60
    /// No input for this long means the human is not present.
    public static let idleThreshold: TimeInterval = 2 * 60
}
