import CoreVideo

enum DepthExtraction {
    /// Kopiuje bufory głębi i pewności do tablic (uwzględnia padding wierszy).
    static func depthMap(depth: CVPixelBuffer, confidence: CVPixelBuffer) -> DepthMap? {
        let w = CVPixelBufferGetWidth(depth)
        let h = CVPixelBufferGetHeight(depth)
        guard w > 0, h > 0,
              CVPixelBufferGetWidth(confidence) == w,
              CVPixelBufferGetHeight(confidence) == h else { return nil }

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        CVPixelBufferLockBaseAddress(confidence, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depth, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
        }
        guard let dBase = CVPixelBufferGetBaseAddress(depth),
              let cBase = CVPixelBufferGetBaseAddress(confidence) else { return nil }
        let dStride = CVPixelBufferGetBytesPerRow(depth)
        let cStride = CVPixelBufferGetBytesPerRow(confidence)

        var d = [Float](repeating: 0, count: w * h)
        var c = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let dRow = dBase.advanced(by: y * dStride).assumingMemoryBound(to: Float.self)
            let cRow = cBase.advanced(by: y * cStride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                d[y * w + x] = dRow[x]
                c[y * w + x] = cRow[x]
            }
        }
        return DepthMap(width: w, height: h, depth: d, confidence: c)
    }
}
