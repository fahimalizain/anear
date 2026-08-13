import CoreGraphics
import Testing

@testable import AnearCore

struct OverlayGeometryTests {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let panelSize = CGSize(width: 200, height: 40)

    @Test func defaultPlacementIsRightAndSlightlyBelowCursor() {
        let cursor = CGPoint(x: 200, y: 200)

        let placement = OverlayGeometry.place(
            cursor: cursor,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        #expect(
            placement.origin
                == CGPoint(
                    x: cursor.x + OverlayGeometry.offsetX,
                    y: cursor.y - OverlayGeometry.offsetY - panelSize.height
                )
        )
        #expect(placement.flippedHorizontal == false)
        #expect(placement.flippedVertical == false)
    }

    @Test func flipsLeftWhenOverflowingRightEdge() {
        let cursor = CGPoint(x: 1300, y: 300)

        let placement = OverlayGeometry.place(
            cursor: cursor,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        #expect(
            placement.origin
                == CGPoint(
                    x: cursor.x - OverlayGeometry.offsetX - panelSize.width,
                    y: cursor.y - OverlayGeometry.offsetY - panelSize.height
                )
        )
        #expect(placement.flippedHorizontal)
        #expect(placement.flippedVertical == false)
    }

    @Test func flipsAboveWhenOverflowingBottomEdge() {
        let cursor = CGPoint(x: 300, y: 30)

        let placement = OverlayGeometry.place(
            cursor: cursor,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        #expect(
            placement.origin
                == CGPoint(
                    x: cursor.x + OverlayGeometry.offsetX,
                    y: cursor.y + OverlayGeometry.offsetY
                )
        )
        #expect(placement.flippedHorizontal == false)
        #expect(placement.flippedVertical)
    }

    @Test func clampsInsideVisibleFrameAfterFlips() {
        // Cursor beyond the bottom-left corner: both flips fire, then the
        // panel is clamped so it still fits entirely inside the frame.
        let cursor = CGPoint(x: 1500, y: -50)

        let placement = OverlayGeometry.place(
            cursor: cursor,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        let panelRect = CGRect(origin: placement.origin, size: panelSize)
        #expect(visibleFrame.contains(panelRect))
        #expect(placement.origin.x == visibleFrame.maxX - panelSize.width)
        #expect(placement.origin.y == visibleFrame.minY)
        #expect(placement.flippedHorizontal)
        #expect(placement.flippedVertical)
    }

    @Test func panelLargerThanVisibleFramePinsToFrameOrigin() {
        let hugePanel = CGSize(width: 2000, height: 1000)
        let cursor = CGPoint(x: 720, y: 450)

        let placement = OverlayGeometry.place(
            cursor: cursor,
            panelSize: hugePanel,
            visibleFrame: visibleFrame
        )

        #expect(placement.origin == visibleFrame.origin)
    }
}
