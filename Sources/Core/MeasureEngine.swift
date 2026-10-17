import Foundation
import simd

struct DepthSample: Equatable {
    var depth: Float?
    var reliability: Reliability
}

struct MeasurementResult: Equatable {
    var millimeters: Double?
    var reliability: Reliability

    var label: String {
        guard let mm = millimeters else { return "—" }
        return "\(Int(mm.rounded())) mm"
    }
}

enum MeasureEngine {
    static let highConfidence: UInt8 = 2
    static let minRange: Float = 0.3
    static let maxRange: Float = 5.0

    static func sample(_ map: DepthMap, at p: NormalizedPoint) -> DepthSample {
        let cx = clamp(Int((p.x * Double(map.width)).rounded(.down)), map.width)
        let cy = clamp(Int((p.y * Double(map.height)).rounded(.down)), map.height)

        let small = window(map, cx, cy, radius: 2)
        if small.total > 0, Double(small.values.count) / Double(small.total) >= 0.3 {
            let med = median(small.values)
            let share = Double(small.values.count) / Double(small.total)
            let agree = Double(small.values.filter { abs($0 - med) <= 0.02 * med }.count)
                / Double(small.values.count)
            let inRange = med >= minRange && med <= maxRange
            let solid = share >= 0.6 && agree >= 0.8
            return DepthSample(depth: med, reliability: (inRange && solid) ? .green : .yellow)
        }
        let large = window(map, cx, cy, radius: 3)
        if large.values.isEmpty { return DepthSample(depth: nil, reliability: .red) }
        return DepthSample(depth: median(large.values), reliability: .yellow)
    }

    static func point3D(_ map: DepthMap, _ k: CameraIntrinsics, at p: NormalizedPoint)
        -> (point: SIMD3<Float>, reliability: Reliability)? {
        let s = sample(map, at: p)
        guard let z = s.depth else { return nil }
        let sx = Double(map.width) / Double(k.imageWidth)
        let sy = Double(map.height) / Double(k.imageHeight)
        let u = p.x * Double(map.width)
        let v = p.y * Double(map.height)
        let x = (u - k.cx * sx) * Double(z) / (k.fx * sx)
        let y = (v - k.cy * sy) * Double(z) / (k.fy * sy)
        return (SIMD3<Float>(Float(x), Float(y), z), s.reliability)
    }

    static func measure(_ map: DepthMap, _ k: CameraIntrinsics,
                        from a: NormalizedPoint, to b: NormalizedPoint) -> MeasurementResult {
        guard let pa = point3D(map, k, at: a), let pb = point3D(map, k, at: b) else {
            return MeasurementResult(millimeters: nil, reliability: .red)
        }
        let mm = Double(simd_distance(pa.point, pb.point)) * 1000
        return MeasurementResult(millimeters: mm, reliability: max(pa.reliability, pb.reliability))
    }

    // MARK: - helpers

    private static func clamp(_ i: Int, _ n: Int) -> Int { min(max(i, 0), n - 1) }

    private static func window(_ m: DepthMap, _ cx: Int, _ cy: Int, radius r: Int)
        -> (values: [Float], total: Int) {
        guard m.width > 0, m.height > 0 else { return ([], 0) }
        var out: [Float] = []
        var total = 0
        for y in max(0, cy - r)...min(m.height - 1, cy + r) {
            for x in max(0, cx - r)...min(m.width - 1, cx + r) {
                total += 1
                let i = y * m.width + x
                let d = m.depth[i]
                if m.confidence[i] == highConfidence, d.isFinite, d > 0 { out.append(d) }
            }
        }
        return (out, total)
    }

    private static func median(_ v: [Float]) -> Float {
        let s = v.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
