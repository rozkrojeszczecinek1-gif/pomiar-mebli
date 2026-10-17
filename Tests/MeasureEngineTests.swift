import XCTest
@testable import R2D2PomiarLidar

final class MeasureEngineTests: XCTestCase {
    // 1920x1440, f=1500 -> przy głębi 256x192: fx_d = 200, cx_d = 128, cy_d = 96
    let k = CameraIntrinsics(fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)
    func plane(_ z: Float) -> DepthMap { .uniform(width: 256, height: 192, depth: z) }
    func p(_ x: Double, _ y: Double) -> NormalizedPoint { NormalizedPoint(x: x, y: y) }

    func testPlaneAtTwoMetersGives1280mm() {
        let r = MeasureEngine.measure(plane(2.0), k, from: p(0.25, 0.5), to: p(0.75, 0.5))
        XCTAssertEqual(r.millimeters!, 1280, accuracy: 0.5)
        XCTAssertEqual(r.reliability, .green)
        XCTAssertEqual(r.label, "1280 mm")
    }

    func testDifferentDepthsUse3DDistance() {
        var m = plane(2.0)
        for y in 0..<192 { for x in 128..<256 { m.depth[y * 256 + x] = 3.0 } }
        let r = MeasureEngine.measure(m, k, from: p(0.25, 0.5), to: p(0.75, 0.5))
        XCTAssertEqual(r.millimeters!, 1886.8, accuracy: 1.0)
    }

    func testIdenticalPointsGiveZero() {
        let r = MeasureEngine.measure(plane(2.0), k, from: p(0.4, 0.4), to: p(0.4, 0.4))
        XCTAssertEqual(r.millimeters!, 0, accuracy: 0.001)
        XCTAssertEqual(r.label, "0 mm")
    }

    func testCornersAndEdgesAreGreenAndDoNotCrash() {
        for (x, y) in [(0.0, 0.0), (1.0, 1.0), (0.0, 1.0), (1.0, 0.0), (0.5, 0.0), (1.0, 0.5)] {
            let s = MeasureEngine.sample(plane(2.0), at: p(x, y))
            XCTAssertEqual(s.depth!, 2.0, accuracy: 0.001, "x=\(x) y=\(y)")
            XCTAssertEqual(s.reliability, .green, "x=\(x) y=\(y)")
        }
    }

    func testAllLowConfidenceIsRedAndNil() {
        let m = DepthMap.uniform(width: 256, height: 192, depth: 2.0, confidence: 0)
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertNil(s.depth)
        XCTAssertEqual(s.reliability, .red)
        let r = MeasureEngine.measure(m, k, from: p(0.2, 0.5), to: p(0.8, 0.5))
        XCTAssertNil(r.millimeters)
        XCTAssertEqual(r.reliability, .red)
        XCTAssertEqual(r.label, "—")
    }

    func testNaNAndZeroPixelsAreIgnored() {
        var m = plane(2.0)
        let c = 96 * 256 + 128
        m.depth[c] = .nan
        m.depth[c + 1] = 0
        m.depth[c - 1] = -1
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertEqual(s.depth!, 2.0, accuracy: 0.001)
    }

    func testLowConfidenceOutliersDoNotAffectMedian() {
        var m = plane(2.0)
        for dy in -1...1 { for dx in -1...1 {
            let i = (96 + dy) * 256 + (128 + dx)
            m.depth[i] = 0.5; m.confidence[i] = 0
        } }
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertEqual(s.depth!, 2.0, accuracy: 0.001)
    }

    func testFewValidPixelsGiveYellowButStillMeasure() {
        var m = DepthMap.uniform(width: 256, height: 192, depth: 2.0, confidence: 0)
        let c = 96 * 256 + 128
        for i in [c, c + 1, c - 1] { m.confidence[i] = 2 }   // 3 z 25 = 12% < 30%, ale 7x7 ma 3 ważne
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertEqual(s.depth!, 2.0, accuracy: 0.001)
        XCTAssertEqual(s.reliability, .yellow)
    }

    func testStepEdgeIsYellow() {
        var m = plane(1.0)
        for y in 0..<192 { for x in 129..<256 { m.depth[y * 256 + x] = 3.0 } }
        // okno 5x5 wokół x=128: kolumny 126..130 -> 3 kolumny 1 m, 2 kolumny 3 m (60/40)
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertEqual(s.reliability, .yellow)
    }

    func testOutOfRangeIsYellow() {
        XCTAssertEqual(MeasureEngine.sample(plane(6.0), at: p(0.5, 0.5)).reliability, .yellow)
        XCTAssertEqual(MeasureEngine.sample(plane(0.2), at: p(0.5, 0.5)).reliability, .yellow)
    }

    func testMeasurementReliabilityIsWorstOfTwoPoints() {
        var m = plane(2.0)
        for i in 0..<(192 * 256) where (i % 256) < 128 { m.confidence[i] = 0 }
        let r = MeasureEngine.measure(m, k, from: p(0.1, 0.5), to: p(0.9, 0.5))
        XCTAssertNil(r.millimeters)           // lewy punkt bez ważnych pikseli
        XCTAssertEqual(r.reliability, .red)
    }
}
