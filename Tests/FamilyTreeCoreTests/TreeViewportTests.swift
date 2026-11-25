import XCTest
@testable import FamilyTreeCore

final class TreeViewportTests: XCTestCase {
    func testZoomKeepsThePointUnderAnOffCenterCursorFixed() {
        var camera = TreeViewport(centerX: 1_000, centerY: 750, scale: 0.8)
        let before = camera.screenPoint(worldX: 1_250, worldY: 600, viewportWidth: 900, viewportHeight: 700)
        camera.zoom(to: 1.7, anchorX: before.x, anchorY: before.y, viewportWidth: 900, viewportHeight: 700)
        let after = camera.screenPoint(worldX: 1_250, worldY: 600, viewportWidth: 900, viewportHeight: 700)
        close(before.x, after.x)
        close(before.y, after.y)
        close(camera.scale, 1.7)
    }

    func testZoomAtViewportCenterDoesNotPan() {
        var camera = TreeViewport(centerX: 400, centerY: 200, scale: 1)
        camera.zoom(to: 0.3, anchorX: 400, anchorY: 300, viewportWidth: 800, viewportHeight: 600)
        close(camera.centerX, 400)
        close(camera.centerY, 200)
    }

    func testZoomIsReversibleAtTheSameAnchor() {
        let original = TreeViewport(centerX: 12_345.5, centerY: 8_765.2, scale: 0.9)
        var camera = original
        camera.zoom(to: 1.8, anchorX: 70, anchorY: 590, viewportWidth: 1_000, viewportHeight: 700)
        camera.zoom(to: original.scale, anchorX: 70, anchorY: 590, viewportWidth: 1_000, viewportHeight: 700)
        close(camera.centerX, original.centerX)
        close(camera.centerY, original.centerY)
        close(camera.scale, original.scale)
    }

    func testDragDistanceIsIndependentOfZoom() {
        for scale in [0.04, 0.3, 0.9, 1.0, 2.0] {
            var camera = TreeViewport(centerX: 500, centerY: 600, scale: scale)
            let before = camera.screenPoint(worldX: 550, worldY: 680, viewportWidth: 900, viewportHeight: 700)
            camera.pan(screenDX: 105, screenDY: -42)
            let after = camera.screenPoint(worldX: 550, worldY: 680, viewportWidth: 900, viewportHeight: 700)
            close(after.x - before.x, 105)
            close(after.y - before.y, -42)
        }
    }

    func testFrameKeepsLargeBranchReadableAndOverviewCanFitIt() {
        var camera = TreeViewport()
        camera.frame(contentWidth: 10_000, contentHeight: 1_600, viewportWidth: 1_000, viewportHeight: 800, minimumReadableScale: 0.9)
        close(camera.scale, 0.9)
        close(camera.centerX, 5_000)
        close(camera.centerY, 800)

        camera.frame(contentWidth: 10_000, contentHeight: 1_600, viewportWidth: 1_000, viewportHeight: 800)
        close(camera.scale, 0.092)
        let topLeft = camera.screenPoint(worldX: 0, worldY: 0, viewportWidth: 1_000, viewportHeight: 800)
        let bottomRight = camera.screenPoint(worldX: 10_000, worldY: 1_600, viewportWidth: 1_000, viewportHeight: 800)
        XCTAssertGreaterThanOrEqual(topLeft.x, 39.999)
        XCTAssertGreaterThanOrEqual(topLeft.y, 39.999)
        XCTAssertLessThanOrEqual(bottomRight.x, 960.001)
        XCTAssertLessThanOrEqual(bottomRight.y, 760.001)
    }

    func testFitUsesLimitingDimensionAndDoesNotEnlargeSmallContent() {
        close(TreeViewport.fitScale(contentWidth: 500, contentHeight: 2_000, viewportWidth: 900, viewportHeight: 700), 0.31)
        close(TreeViewport.fitScale(contentWidth: 2_000, contentHeight: 500, viewportWidth: 900, viewportHeight: 700), 0.41)
        close(TreeViewport.fitScale(contentWidth: 200, contentHeight: 150, viewportWidth: 900, viewportHeight: 700), 1)
    }

    func testFocusPreservesZoomUnlessReadableScaleIsRequested() {
        var camera = TreeViewport(centerX: 100, centerY: 200, scale: 0.08)
        camera.focus(x: 1_500, y: 800)
        close(camera.scale, 0.08)
        let centered = camera.screenPoint(worldX: 1_500, worldY: 800, viewportWidth: 900, viewportHeight: 700)
        close(centered.x, 450)
        close(centered.y, 350)
        camera.focus(x: 1_500, y: 800, readableScale: 1)
        close(camera.scale, 1)
    }

    func testZoomLimitsPreserveCursorAnchorEvenWhenClamped() {
        var camera = TreeViewport(centerX: 200, centerY: 300)
        let before = camera.screenPoint(worldX: 350, worldY: 410, viewportWidth: 800, viewportHeight: 600)
        camera.zoom(to: 50, anchorX: before.x, anchorY: before.y, viewportWidth: 800, viewportHeight: 600)
        close(camera.scale, TreeViewport.maximumScale)
        let afterMaximum = camera.screenPoint(worldX: 350, worldY: 410, viewportWidth: 800, viewportHeight: 600)
        close(afterMaximum.x, before.x)
        close(afterMaximum.y, before.y)
        camera.zoom(to: -10, anchorX: before.x, anchorY: before.y, viewportWidth: 800, viewportHeight: 600)
        close(camera.scale, TreeViewport.minimumScale)
        let afterMinimum = camera.screenPoint(worldX: 350, worldY: 410, viewportWidth: 800, viewportHeight: 600)
        close(afterMinimum.x, before.x)
        close(afterMinimum.y, before.y)
    }

    func testZeroAndNonFiniteInputsNeverPoisonCameraState() {
        var camera = TreeViewport(centerX: .nan, centerY: .infinity, scale: .nan)
        assertFinite(camera)
        camera.centerX = .nan
        camera.centerY = -.infinity
        camera.scale = 0
        camera.pan(screenDX: .infinity, screenDY: .nan)
        assertFinite(camera)
        camera.zoom(to: .infinity, anchorX: .nan, anchorY: .infinity, viewportWidth: 0, viewportHeight: -.infinity)
        assertFinite(camera)
        camera.focus(x: .nan, y: .infinity, readableScale: -.infinity)
        assertFinite(camera)
        camera.frame(contentWidth: .nan, contentHeight: -1, viewportWidth: 0, viewportHeight: 0, minimumReadableScale: .infinity)
        assertFinite(camera)
        close(TreeViewport.fitScale(contentWidth: 0, contentHeight: 0, viewportWidth: 0, viewportHeight: 0), 1)
        let point = camera.screenPoint(worldX: .infinity, worldY: .nan, viewportWidth: .infinity, viewportHeight: 0)
        XCTAssertTrue(point.x.isFinite && point.y.isFinite)

        camera.pan(screenDX: Double.greatestFiniteMagnitude, screenDY: -Double.greatestFiniteMagnitude)
        assertFinite(camera)
        camera.zoom(to: 2, anchorX: Double.greatestFiniteMagnitude, anchorY: -Double.greatestFiniteMagnitude, viewportWidth: 1, viewportHeight: 1)
        assertFinite(camera)
        let extreme = camera.screenPoint(worldX: Double.greatestFiniteMagnitude, worldY: -Double.greatestFiniteMagnitude, viewportWidth: 1, viewportHeight: 1)
        XCTAssertTrue(extreme.x.isFinite && extreme.y.isFinite)
    }

    private func close(_ left: Double, _ right: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(abs(left - right) < 0.000_001, "\(left) is not approximately \(right)", file: file, line: line)
    }

    private func assertFinite(_ camera: TreeViewport, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(camera.centerX.isFinite && camera.centerY.isFinite && camera.scale.isFinite, file: file, line: line)
        XCTAssertGreaterThanOrEqual(camera.scale, TreeViewport.minimumScale, file: file, line: line)
        XCTAssertLessThanOrEqual(camera.scale, TreeViewport.maximumScale, file: file, line: line)
    }
}
