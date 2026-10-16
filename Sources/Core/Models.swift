import Foundation

struct NormalizedPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct CameraIntrinsics: Codable, Equatable {
    var fx: Double
    var fy: Double
    var cx: Double
    var cy: Double
    var imageWidth: Int
    var imageHeight: Int
}

enum Reliability: Int, Codable, Comparable {
    case green = 0, yellow = 1, red = 2
    static func < (l: Reliability, r: Reliability) -> Bool { l.rawValue < r.rawValue }
}

struct DepthMap: Equatable {
    let width: Int
    let height: Int
    var depth: [Float]
    var confidence: [UInt8]

    static func uniform(width: Int, height: Int, depth: Float, confidence: UInt8 = 2) -> DepthMap {
        DepthMap(width: width, height: height,
                 depth: [Float](repeating: depth, count: width * height),
                 confidence: [UInt8](repeating: confidence, count: width * height))
    }
}
