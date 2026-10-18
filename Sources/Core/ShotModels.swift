import Foundation

struct Measurement: Codable, Identifiable, Equatable {
    var id: UUID
    var a: NormalizedPoint
    var b: NormalizedPoint
    var manualMM: Double?

    init(id: UUID = UUID(), a: NormalizedPoint, b: NormalizedPoint, manualMM: Double? = nil) {
        self.id = id
        self.a = a
        self.b = b
        self.manualMM = manualMM
    }
}

struct ShotMeta: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var intrinsics: CameraIntrinsics
    var depthWidth: Int
    var depthHeight: Int
    var orientation: ImageOrientation
    var measurements: [Measurement]
    var calibrationFactor: Double?
}

struct CapturedShot {
    var jpeg: Data
    var depth: DepthMap
    var intrinsics: CameraIntrinsics
    var orientation: ImageOrientation
}

extension DepthMap {
    /// Float32 (little-endian, wiersz po wierszu), potem UInt8 pewności.
    func encoded() -> Data {
        var data = depth.withUnsafeBufferPointer { Data(buffer: $0) }
        data.append(contentsOf: confidence)
        return data
    }

    init?(data: Data, width: Int, height: Int) {
        let n = width * height
        guard width > 0, height > 0, data.count == n * 4 + n else { return nil }
        var floats = [Float](repeating: 0, count: n)
        floats.withUnsafeMutableBytes { _ = data.copyBytes(to: $0, from: 0..<(n * 4)) }
        let conf = [UInt8](data.subdata(in: (n * 4)..<data.count))
        self.init(width: width, height: height, depth: floats, confidence: conf)
    }
}
