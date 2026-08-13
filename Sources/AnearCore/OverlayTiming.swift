import Foundation

/// Product timing constants for the cursor overlay: how long the pill stays
/// fully visible, and how long it takes to fade out afterwards.
public enum OverlayTiming {
    /// Time the pill stays fully visible before the fade begins.
    public static let holdDuration: TimeInterval = 4.0
    /// Time the pill takes to fade to invisible.
    public static let fadeDuration: TimeInterval = 1.25
    /// Total time from spawn until the pill is fully gone.
    public static var totalVisibleDuration: TimeInterval { holdDuration + fadeDuration }
}
