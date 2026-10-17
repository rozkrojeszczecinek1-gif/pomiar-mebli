import XCTest
@testable import R2D2PomiarLidar

final class ShotStoreTests: XCTestCase {
    var root: URL!
    var store: ShotStore!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("shots-\(UUID().uuidString)")
        store = ShotStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    let k = CameraIntrinsics(fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)
    func shot() -> CapturedShot {
        var d = DepthMap.uniform(width: 4, height: 3, depth: 1.5)
        d.depth[5] = 2.25; d.confidence[7] = 0
        return CapturedShot(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), depth: d, intrinsics: k, orientation: .right)
    }

    func testDepthMapEncodeDecodeRoundTrip() {
        let d = shot().depth
        let back = DepthMap(data: d.encoded(), width: 4, height: 3)
        XCTAssertEqual(back, d)
    }

    func testDepthMapDecodeRejectsWrongSize() {
        XCTAssertNil(DepthMap(data: Data(count: 10), width: 4, height: 3))
        XCTAssertNil(DepthMap(data: Data(), width: 0, height: 0))
    }

    func testSaveListLoad() throws {
        let meta = try store.save(shot(), name: "Kuchnia", now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(store.list(), [meta])
        XCTAssertEqual(store.loadDepth(meta), shot().depth)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: meta.id)), Data([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertEqual(meta.orientation, .right)
        XCTAssertEqual(meta.depthWidth, 4)
    }

    func testListIsNewestFirst() throws {
        let a = try store.save(shot(), name: "A", now: Date(timeIntervalSince1970: 1_000))
        let b = try store.save(shot(), name: "B", now: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(store.list().map(\.id), [b.id, a.id])
    }

    func testUpdatePersistsMeasurements() throws {
        // pełne sekundy: ISO8601 w meta.json nie zachowuje ułamków
        var meta = try store.save(shot(), name: "X", now: Date(timeIntervalSince1970: 1_000))
        meta.measurements.append(Measurement(a: NormalizedPoint(x: 0.1, y: 0.2), b: NormalizedPoint(x: 0.9, y: 0.8)))
        meta.name = "Nowa nazwa"
        try store.update(meta)
        XCTAssertEqual(store.list().first, meta)
    }

    func testDeleteRemovesFiles() throws {
        let meta = try store.save(shot(), name: "X", now: Date())
        store.delete(id: meta.id)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: meta.id).path))
    }

    func testCorruptMetaIsSkippedAndMissingDepthIsNil() throws {
        let good = try store.save(shot(), name: "OK", now: Date())
        let bad = try store.save(shot(), name: "BAD", now: Date())
        try Data("nie json".utf8).write(to: root.appendingPathComponent(bad.id.uuidString).appendingPathComponent("meta.json"))
        XCTAssertEqual(store.list().map(\.id), [good.id])
        try FileManager.default.removeItem(at: root.appendingPathComponent(good.id.uuidString).appendingPathComponent("depth.bin"))
        XCTAssertNil(store.loadDepth(good))
    }
}
