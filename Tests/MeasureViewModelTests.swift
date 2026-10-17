import XCTest
@testable import R2D2PomiarLidar

@MainActor
final class MeasureViewModelTests: XCTestCase {
    var root: URL!
    var store: ShotStore!
    let k = CameraIntrinsics(fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vm-\(UUID().uuidString)")
        store = ShotStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func p(_ x: Double, _ y: Double) -> NormalizedPoint { NormalizedPoint(x: x, y: y) }

    func makeVM(depth: DepthMap = .uniform(width: 256, height: 192, depth: 2.0)) throws -> MeasureViewModel {
        let shot = CapturedShot(jpeg: Data([1]), depth: depth, intrinsics: k, orientation: .right)
        let meta = try store.save(shot, name: "T", now: Date(timeIntervalSince1970: 1_000))
        return MeasureViewModel(meta: meta, depth: depth, store: store)
    }

    func testTwoPlacesCreateMeasurementAndThirdStartsNext() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5))
        XCTAssertEqual(vm.pendingA, p(0.25, 0.5))
        XCTAssertTrue(vm.meta.measurements.isEmpty)
        vm.place(at: p(0.75, 0.5))
        XCTAssertNil(vm.pendingA)
        XCTAssertEqual(vm.meta.measurements.count, 1)
        XCTAssertEqual(vm.result(for: vm.meta.measurements[0]).label, "1280 mm")
        vm.place(at: p(0.1, 0.1))
        XCTAssertEqual(vm.pendingA, p(0.1, 0.1))
    }

    func testPlacePersistsToStore() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        XCTAssertEqual(store.list().first?.measurements.count, 1)
    }

    func testHitFindsNearestEndpointWithinRadius() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        let id = vm.meta.measurements[0].id
        let project: (NormalizedPoint) -> CGPoint = { CGPoint(x: $0.x * 400, y: $0.y * 300) }
        XCTAssertEqual(vm.hit(at: CGPoint(x: 105, y: 152), radius: 24, project: project), .a(id))
        XCTAssertEqual(vm.hit(at: CGPoint(x: 296, y: 148), radius: 24, project: project), .b(id))
        XCTAssertNil(vm.hit(at: CGPoint(x: 200, y: 150), radius: 24, project: project))
    }

    func testHitFindsPendingPoint() throws {
        let vm = try makeVM()
        vm.place(at: p(0.5, 0.5))
        let project: (NormalizedPoint) -> CGPoint = { CGPoint(x: $0.x * 400, y: $0.y * 300) }
        XCTAssertEqual(vm.hit(at: CGPoint(x: 200, y: 150), radius: 24, project: project), .pending)
    }

    func testMoveChangesResultAndCommitPersists() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        let m = vm.meta.measurements[0]
        vm.move(.b(m.id), to: p(0.50, 0.5))
        XCTAssertEqual(vm.result(for: vm.meta.measurements[0]).label, "640 mm")
        vm.commit()
        XCTAssertEqual(store.list().first?.measurements[0].b, p(0.5, 0.5))
    }

    func testDeleteAndRename() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        vm.rename("Szafa")
        vm.delete(vm.meta.measurements[0].id)
        XCTAssertTrue(vm.meta.measurements.isEmpty)
        XCTAssertEqual(store.list().first?.name, "Szafa")
        XCTAssertEqual(store.list().first?.measurements.count, 0)
    }

    func testPointWithoutValidDepthGivesDashAndDoesNotCrash() throws {
        let vm = try makeVM(depth: .uniform(width: 256, height: 192, depth: 2.0, confidence: 0))
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        let r = vm.result(for: vm.meta.measurements[0])
        XCTAssertEqual(r.label, "—")
        XCTAssertEqual(r.reliability, .red)
    }

    func testCancelPending() throws {
        let vm = try makeVM()
        vm.place(at: p(0.5, 0.5)); vm.cancelPending()
        XCTAssertNil(vm.pendingA)
    }
}
