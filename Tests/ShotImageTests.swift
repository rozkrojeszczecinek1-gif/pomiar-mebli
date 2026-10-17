import XCTest
import UIKit
@testable import R2D2PomiarLidar

final class ShotImageTests: XCTestCase {
    func testLoadAppliesOrientationAndSwapsDisplayedSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("img-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShotStore(root: root)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: f).image { c in
            UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }.jpegData(compressionQuality: 0.9)!
        let k = CameraIntrinsics(fx: 1, fy: 1, cx: 1, cy: 1, imageWidth: 200, imageHeight: 100)
        let meta = try store.save(CapturedShot(jpeg: jpeg, depth: .uniform(width: 2, height: 2, depth: 1),
                                               intrinsics: k, orientation: .right), name: "T", now: Date())
        let img = try XCTUnwrap(ShotImage.load(meta, store: store))
        XCTAssertEqual(img.size.width, 100)     // obrócony: szerokość = wysokość sensora
        XCTAssertEqual(img.size.height, 200)
    }

    func testLoadMissingFileReturnsNil() {
        let store = ShotStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString)"))
        let k = CameraIntrinsics(fx: 1, fy: 1, cx: 1, cy: 1, imageWidth: 1, imageHeight: 1)
        let meta = ShotMeta(id: UUID(), name: "", createdAt: Date(), intrinsics: k, depthWidth: 1, depthHeight: 1,
                            orientation: .up, measurements: [])
        XCTAssertNil(ShotImage.load(meta, store: store))
    }
}
