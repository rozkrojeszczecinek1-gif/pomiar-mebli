import XCTest
import CoreVideo
@testable import PomiarMebli

final class DepthExtractionTests: XCTestCase {
    func makeBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary   // wymusza padding wierszy
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, format, attrs, &pb), kCVReturnSuccess)
        return pb!
    }

    func testExtractsValuesIgnoringRowPadding() {
        let d = makeBuffer(width: 5, height: 3, format: kCVPixelFormatType_OneComponent32Float)
        let c = makeBuffer(width: 5, height: 3, format: kCVPixelFormatType_OneComponent8)
        CVPixelBufferLockBaseAddress(d, []); CVPixelBufferLockBaseAddress(c, [])
        let ds = CVPixelBufferGetBytesPerRow(d), cs = CVPixelBufferGetBytesPerRow(c)
        for y in 0..<3 { for x in 0..<5 {
            floatRow(d, y, ds)[x] = Float(y * 10 + x)
            byteRow(c, y, cs)[x] = UInt8(x % 3)
        } }
        CVPixelBufferUnlockBaseAddress(d, []); CVPixelBufferUnlockBaseAddress(c, [])

        let m = DepthExtraction.depthMap(depth: d, confidence: c)!
        XCTAssertEqual(m.width, 5); XCTAssertEqual(m.height, 3)
        XCTAssertEqual(m.depth[2 * 5 + 4], 24)
        XCTAssertEqual(m.depth[1 * 5 + 2], 12)
        XCTAssertEqual(m.confidence[4], 1)
    }

    func testMismatchedSizesReturnNil() {
        let d = makeBuffer(width: 5, height: 3, format: kCVPixelFormatType_OneComponent32Float)
        let c = makeBuffer(width: 4, height: 3, format: kCVPixelFormatType_OneComponent8)
        XCTAssertNil(DepthExtraction.depthMap(depth: d, confidence: c))
    }

    func testSimulatorHasNoLiDAR() {
        // Testy działają na symulatorze: widok kamery musi pokazać komunikat, a nie uruchamiać sesji.
        XCTAssertFalse(CaptureController.isSupported)
    }

    private func floatRow(_ b: CVPixelBuffer, _ y: Int, _ stride: Int) -> UnsafeMutablePointer<Float> {
        CVPixelBufferGetBaseAddress(b)!.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
    }
    private func byteRow(_ b: CVPixelBuffer, _ y: Int, _ stride: Int) -> UnsafeMutablePointer<UInt8> {
        CVPixelBufferGetBaseAddress(b)!.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
    }
}
