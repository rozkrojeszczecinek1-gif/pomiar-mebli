import XCTest
import UIKit
@testable import R2D2PomiarLidar

final class GeometryTests: XCTestCase {
    func p(_ x: Double, _ y: Double) -> NormalizedPoint { NormalizedPoint(x: x, y: y) }
    func assertEqual(_ a: NormalizedPoint, _ b: NormalizedPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, file: file, line: line)
    }

    func testRightRotatesCornersClockwise() {
        assertEqual(SensorGeometry.toDisplay(p(0, 0), .right), p(1, 0))
        assertEqual(SensorGeometry.toDisplay(p(1, 0), .right), p(1, 1))
        assertEqual(SensorGeometry.toDisplay(p(1, 1), .right), p(0, 1))
        assertEqual(SensorGeometry.toDisplay(p(0, 1), .right), p(0, 0))
    }

    func testLeftRotatesCornersCounterClockwise() {
        assertEqual(SensorGeometry.toDisplay(p(0, 0), .left), p(0, 1))
        assertEqual(SensorGeometry.toDisplay(p(1, 0), .left), p(0, 0))
    }

    func testDownIsPointReflection() {
        assertEqual(SensorGeometry.toDisplay(p(0.2, 0.7), .down), p(0.8, 0.3))
    }

    func testRoundTripForAllOrientations() {
        for o in [ImageOrientation.up, .down, .left, .right] {
            for pt in [p(0, 0), p(1, 1), p(0.3, 0.8), p(0.5, 0.5), p(1, 0)] {
                assertEqual(SensorGeometry.toSensor(SensorGeometry.toDisplay(pt, o), o), pt)
            }
        }
    }

    func testDisplayedSizeSwapsForSideways() {
        XCTAssertEqual(SensorGeometry.displayedSize(sensorWidth: 1920, sensorHeight: 1440, orientation: .right).width, 1440)
        XCTAssertEqual(SensorGeometry.displayedSize(sensorWidth: 1920, sensorHeight: 1440, orientation: .up).width, 1920)
    }

    func testDeviceOrientationMapping() {
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .portrait), .right)
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .portraitUpsideDown), .left)
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .landscapeLeft), .up)
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .landscapeRight), .down)
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .faceUp), .right)   // nieznana -> pion
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .unknown), .right)
    }

    func testLayoutFitsAndCenters() {
        let l = ImageLayout(container: CGSize(width: 400, height: 800), displayed: CGSize(width: 300, height: 400))
        // skala = min(400/300, 800/400) = 4/3 -> 400 x 533.33, wyśrodkowane w pionie
        XCTAssertEqual(l.rect.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(l.rect.minY, 400.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(l.rect.width, 400, accuracy: 1e-9)
        XCTAssertEqual(l.rect.height, 1600.0 / 3.0, accuracy: 1e-9)
        let v = l.viewPoint(p(0.5, 0.5))
        XCTAssertEqual(v.x, 200, accuracy: 1e-9)
        XCTAssertEqual(v.y, 400, accuracy: 1e-9)
        assertEqual(l.displayPoint(CGPoint(x: 200, y: 400)), p(0.5, 0.5))
    }

    func testDisplayPointIsClampedOutsideImage() {
        let l = ImageLayout(container: CGSize(width: 400, height: 800), displayed: CGSize(width: 300, height: 400))
        assertEqual(l.displayPoint(CGPoint(x: -50, y: 0)), p(0, 0))
        assertEqual(l.displayPoint(CGPoint(x: 999, y: 999)), p(1, 1))
    }

    func testZeroSizesDoNotCrash() {
        let l = ImageLayout(container: .zero, displayed: CGSize(width: 10, height: 10))
        XCTAssertEqual(l.rect, .zero)
        assertEqual(l.displayPoint(CGPoint(x: 5, y: 5)), p(0, 0))
    }
}
