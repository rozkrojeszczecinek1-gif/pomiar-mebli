import XCTest
import UIKit
@testable import PomiarMebli

final class OverlayRendererTests: XCTestCase {
    let k = CameraIntrinsics(fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)

    func whiteImage(_ w: Int, _ h: Int) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    /// Kolor piksela (x, y) liczony od lewego górnego rogu obrazu.
    func pixel(_ img: UIImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img.cgImage!, in: CGRect(x: -x, y: -(img.cgImage!.height - 1 - y),
                                          width: img.cgImage!.width, height: img.cgImage!.height))
        return (px[0], px[1], px[2])
    }

    func testLinesUseEngineAndConvertToDisplayPixels() {
        let meta = ShotMeta(id: UUID(), name: "T", createdAt: Date(), intrinsics: k, depthWidth: 256, depthHeight: 192,
                            orientation: .up,
                            measurements: [Measurement(a: NormalizedPoint(x: 0.25, y: 0.5), b: NormalizedPoint(x: 0.75, y: 0.5))])
        let lines = OverlayRenderer.lines(for: meta, depth: .uniform(width: 256, height: 192, depth: 2.0),
                                          displayedSize: CGSize(width: 1920, height: 1440))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].label, "1280 mm")
        XCTAssertEqual(lines[0].a.x, 480, accuracy: 0.001)
        XCTAssertEqual(lines[0].b.y, 720, accuracy: 0.001)
    }

    func testLinesRespectOrientation() {
        let meta = ShotMeta(id: UUID(), name: "T", createdAt: Date(), intrinsics: k, depthWidth: 256, depthHeight: 192,
                            orientation: .right,
                            measurements: [Measurement(a: NormalizedPoint(x: 0, y: 0), b: NormalizedPoint(x: 1, y: 0))])
        let lines = OverlayRenderer.lines(for: meta, depth: .uniform(width: 256, height: 192, depth: 2.0),
                                          displayedSize: CGSize(width: 1440, height: 1920))
        XCTAssertEqual(lines[0].a, CGPoint(x: 1440, y: 0))      // sensor (0,0) -> prawy górny
        XCTAssertEqual(lines[0].b, CGPoint(x: 1440, y: 1920))   // sensor (1,0) -> prawy dolny
    }

    func testRenderKeepsSizeAndDrawsOnImage() throws {
        let img = whiteImage(400, 300)
        let line = OverlayLine(a: CGPoint(x: 50, y: 150), b: CGPoint(x: 350, y: 150), label: "1280 mm", reliability: .green)
        let data = try XCTUnwrap(OverlayRenderer.render(image: img, lines: [line], title: "Test"))
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(out.size.width * out.scale, 400)
        XCTAssertEqual(out.size.height * out.scale, 300)
        let p = pixel(out, 50, 150)                  // koniec odcinka — nie biały
        XCTAssertTrue(p.r < 250 || p.g < 250 || p.b < 250)
        let q = pixel(out, 380, 20)                  // narożnik bez rysunku — biały
        XCTAssertGreaterThan(q.r, 240)
    }

    func testRenderWithoutLinesStillProducesJPEG() {
        XCTAssertNotNil(OverlayRenderer.render(image: whiteImage(100, 100), lines: [], title: nil))
    }
}
