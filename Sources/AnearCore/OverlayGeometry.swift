import Foundation
import CoreGraphics

/// Where an overlay panel should be placed relative to the cursor.
public struct OverlayPlacement: Sendable, Equatable {
    /// Panel origin in macOS screen coordinates (bottom-left origin, Y up).
    public var origin: CGPoint
    /// True when the panel was moved to the left of the cursor.
    public var flippedHorizontal: Bool
    /// True when the panel was moved above the cursor.
    public var flippedVertical: Bool

    public init(origin: CGPoint, flippedHorizontal: Bool, flippedVertical: Bool) {
        self.origin = origin
        self.flippedHorizontal = flippedHorizontal
        self.flippedVertical = flippedVertical
    }
}

/// Deterministic placement math for the cursor overlay. Pure geometry — no
/// AppKit, no randomness.
///
/// Coordinates are macOS screen coordinates: origin at the bottom-left of the
/// main display, Y increasing upward.
public enum OverlayGeometry {
    /// Horizontal gap between the cursor and the panel edge.
    public static let offsetX: CGFloat = 22
    /// Vertical gap between the cursor and the panel edge.
    public static let offsetY: CGFloat = 8
    /// Maximum panel width the placement math is designed for.
    public static let maxWidth: CGFloat = 340

    /// Default placement: to the right of and slightly below the cursor.
    /// Flips left if the panel would pass `visibleFrame.maxX`.
    /// Flips above if the panel would pass `visibleFrame.minY`.
    /// Then clamps so the entire panel stays inside `visibleFrame`.
    /// If the panel is larger than the frame, origin == visibleFrame.origin.
    public static func place(
        cursor: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> OverlayPlacement {
        // Frame bounds in screen coordinates (origin is bottom-left).
        let minX = visibleFrame.origin.x
        let minY = visibleFrame.origin.y
        let maxX = minX + visibleFrame.width
        let maxY = minY + visibleFrame.height

        // Default: to the right of and slightly below the cursor.
        var origin = CGPoint(
            x: cursor.x + offsetX,
            y: cursor.y - offsetY - panelSize.height
        )
        var flippedHorizontal = false
        var flippedVertical = false

        // Flip left if the panel would pass the right edge.
        if origin.x + panelSize.width > maxX {
            origin.x = cursor.x - offsetX - panelSize.width
            flippedHorizontal = true
        }

        // Flip above if the panel would pass the bottom edge.
        if origin.y < minY {
            origin.y = cursor.y + offsetY
            flippedVertical = true
        }

        // A panel larger than the frame cannot be clamped meaningfully; pin
        // it to the frame origin instead.
        if panelSize.width > visibleFrame.width || panelSize.height > visibleFrame.height {
            return OverlayPlacement(
                origin: visibleFrame.origin,
                flippedHorizontal: flippedHorizontal,
                flippedVertical: flippedVertical
            )
        }

        // Clamp so the entire panel stays inside the frame.
        origin.x = min(max(origin.x, minX), maxX - panelSize.width)
        origin.y = min(max(origin.y, minY), maxY - panelSize.height)

        return OverlayPlacement(
            origin: origin,
            flippedHorizontal: flippedHorizontal,
            flippedVertical: flippedVertical
        )
    }
}
