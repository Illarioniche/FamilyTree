import Foundation

/// A platform-independent camera. World coordinates use the tree layout's points;
/// screen coordinates start at the viewport's top-left corner.
///
/// Keeping the camera's scale independent of the complete tree's size allows a
/// readable branch view. Fitting an entire tree is an explicit overview operation.
public struct TreeViewport: Equatable, Sendable {
    public static let minimumScale: Double = 0.04
    public static let maximumScale: Double = 2.0

    public var centerX: Double
    public var centerY: Double
    public var scale: Double

    public init(centerX: Double = 0, centerY: Double = 0, scale: Double = 1) {
        self.centerX = centerX.isFinite ? centerX : 0
        self.centerY = centerY.isFinite ? centerY : 0
        self.scale = Self.validScale(scale, fallback: 1)
    }

    /// Moves the drawing with the pointer by a distance measured in screen points.
    /// A 100-point drag moves the drawing 100 points at every zoom level.
    public mutating func pan(screenDX: Double, screenDY: Double) {
        normalize()
        if screenDX.isFinite {
            let next = centerX - screenDX / scale
            if next.isFinite { centerX = next }
        }
        if screenDY.isFinite {
            let next = centerY - screenDY / scale
            if next.isFinite { centerY = next }
        }
    }

    /// Changes scale without moving the world point beneath the cursor.
    public mutating func zoom(
        to requestedScale: Double,
        anchorX: Double,
        anchorY: Double,
        viewportWidth: Double,
        viewportHeight: Double
    ) {
        normalize()
        let nextScale = Self.validScale(requestedScale, fallback: scale)
        let halfWidth = Self.validExtent(viewportWidth) / 2
        let halfHeight = Self.validExtent(viewportHeight) / 2
        let offsetX = (anchorX.isFinite ? anchorX : halfWidth) - halfWidth
        let offsetY = (anchorY.isFinite ? anchorY : halfHeight) - halfHeight
        // The difference form avoids adding and subtracting a large world
        // coordinate twice when zooming around the viewport edge.
        let nextX = centerX + offsetX * (1 / scale - 1 / nextScale)
        let nextY = centerY + offsetY * (1 / scale - 1 / nextScale)
        if nextX.isFinite { centerX = nextX }
        if nextY.isFinite { centerY = nextY }
        scale = nextScale
    }

    public func screenPoint(
        worldX: Double,
        worldY: Double,
        viewportWidth: Double,
        viewportHeight: Double
    ) -> (x: Double, y: Double) {
        let valid = Self(centerX: centerX, centerY: centerY, scale: scale)
        let halfWidth = Self.validExtent(viewportWidth) / 2
        let halfHeight = Self.validExtent(viewportHeight) / 2
        let x = ((worldX.isFinite ? worldX : valid.centerX) - valid.centerX) * valid.scale + halfWidth
        let y = ((worldY.isFinite ? worldY : valid.centerY) - valid.centerY) * valid.scale + halfHeight
        return (x.isFinite ? x : halfWidth, y.isFinite ? y : halfHeight)
    }

    /// Scale that fits both dimensions, with padding points on each edge.
    /// Never enlarges a small tree. Empty or not-yet-measured views use 100%.
    public static func fitScale(
        contentWidth: Double,
        contentHeight: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        padding: Double = 40
    ) -> Double {
        guard contentWidth.isFinite, contentWidth > 0,
              contentHeight.isFinite, contentHeight > 0,
              viewportWidth.isFinite, viewportWidth > 0,
              viewportHeight.isFinite, viewportHeight > 0 else { return 1 }
        let inset = padding.isFinite ? max(0, padding) : 0
        let availableWidth = max(1, viewportWidth - 2 * inset)
        let availableHeight = max(1, viewportHeight - 2 * inset)
        let fitted = min(availableWidth / contentWidth, availableHeight / contentHeight)
        return min(1, validScale(fitted, fallback: minimumScale))
    }

    /// Frames the content, optionally retaining a readable lower bound.
    /// If the lower bound exceeds fit scale, offscreen branches remain available
    /// by panning; they are never removed from the data.
    public mutating func frame(
        contentWidth: Double,
        contentHeight: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        minimumReadableScale: Double = 0
    ) {
        centerX = contentWidth.isFinite && contentWidth > 0 ? contentWidth / 2 : 0
        centerY = contentHeight.isFinite && contentHeight > 0 ? contentHeight / 2 : 0
        let readable = minimumReadableScale.isFinite ? min(1, max(0, minimumReadableScale)) : 0
        scale = max(readable, Self.fitScale(
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        ))
        normalize()
    }

    /// Puts a person at the center. Passing a scale restores a readable close-up;
    /// leaving it nil preserves the user's current zoom.
    public mutating func focus(x: Double, y: Double, readableScale: Double? = nil) {
        normalize()
        if x.isFinite { centerX = x }
        if y.isFinite { centerY = y }
        if let readableScale { scale = Self.validScale(readableScale, fallback: scale) }
    }

    private mutating func normalize() {
        if !centerX.isFinite { centerX = 0 }
        if !centerY.isFinite { centerY = 0 }
        scale = Self.validScale(scale, fallback: 1)
    }

    private static func validScale(_ value: Double, fallback: Double) -> Double {
        let finite = value.isFinite ? value : fallback
        return min(maximumScale, max(minimumScale, finite))
    }

    private static func validExtent(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 1
    }
}
