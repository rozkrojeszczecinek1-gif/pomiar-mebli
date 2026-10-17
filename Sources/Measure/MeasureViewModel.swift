import Foundation
import CoreGraphics

enum DragTarget: Equatable {
    case a(UUID)
    case b(UUID)
    case pending
}

@MainActor
final class MeasureViewModel: ObservableObject {
    @Published private(set) var meta: ShotMeta
    @Published private(set) var pendingA: NormalizedPoint?
    @Published var saveError = false
    let depth: DepthMap
    private let store: ShotStore
    private var resultsCache: [UUID: MeasurementResult] = [:]

    init(meta: ShotMeta, depth: DepthMap, store: ShotStore) {
        self.meta = meta
        self.depth = depth
        self.store = store
    }

    func result(for m: Measurement) -> MeasurementResult {
        if let cached = resultsCache[m.id] { return cached }
        let r = MeasureEngine.measure(depth, meta.intrinsics, from: m.a, to: m.b)
        resultsCache[m.id] = r
        return r
    }

    func hit(at point: CGPoint, radius: CGFloat,
             project: (NormalizedPoint) -> CGPoint) -> DragTarget? {
        var best: (target: DragTarget, dist: CGFloat)?
        func consider(_ t: DragTarget, _ n: NormalizedPoint) {
            let q = project(n)
            let d = hypot(q.x - point.x, q.y - point.y)
            if d <= radius, d < (best?.dist ?? .infinity) { best = (t, d) }
        }
        if let a = pendingA { consider(.pending, a) }
        for m in meta.measurements {
            consider(.a(m.id), m.a)
            consider(.b(m.id), m.b)
        }
        return best?.target
    }

    func move(_ target: DragTarget, to p: NormalizedPoint) {
        switch target {
        case .pending:
            pendingA = p
        case .a(let id):
            mutate(id) { $0.a = p }
            resultsCache.removeValue(forKey: id)
        case .b(let id):
            mutate(id) { $0.b = p }
            resultsCache.removeValue(forKey: id)
        }
    }

    func place(at p: NormalizedPoint) {
        if let a = pendingA {
            meta.measurements.append(Measurement(a: a, b: p))
            pendingA = nil
            persist()
        } else {
            pendingA = p
        }
    }

    func commit() { persist() }

    func delete(_ id: UUID) {
        meta.measurements.removeAll { $0.id == id }
        resultsCache.removeValue(forKey: id)
        persist()
    }

    func rename(_ name: String) {
        meta.name = name
        persist()
    }

    func cancelPending() { pendingA = nil }

    private func mutate(_ id: UUID, _ change: (inout Measurement) -> Void) {
        guard let i = meta.measurements.firstIndex(where: { $0.id == id }) else { return }
        change(&meta.measurements[i])
    }

    private func persist() {
        do {
            try store.update(meta)
        } catch {
            saveError = true
        }
    }
}
