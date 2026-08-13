import Foundation

/// Formats a remaining wait as a compact human countdown like `1h 10m 10s`
/// for the menu's read-only status item.
///
/// Seconds are ceiled so a sub-second leftover still displays as `1s` while
/// the scheduler has not yet fired, and zero-valued units are dropped so a
/// short wait reads `30s` rather than `0h 0m 30s`.
public enum CountdownFormat {
    /// Formats the remaining time as a compact `h/m/s` countdown, with zero
    /// units omitted (except the whole zero, which is `0s`).
    public static func display(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        guard total > 0 else { return "0s" }

        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if seconds > 0 { parts.append("\(seconds)s") }
        return parts.joined(separator: " ")
    }
}
