import ARKit
import SceneKit
import SwiftUI

// MARK: - Data types

struct RawCameraFrame {
    let viewMatrix: simd_float4x4   // world-to-camera (camera.transform.inverse)
    let intrinsics: simd_float3x3
    let colorBuffer: CVPixelBuffer
    let pixelWidth: Int
    let pixelHeight: Int
}

struct ColoredMeshData {
    var positions: [SIMD3<Float>]
    var colors: [SIMD3<Float>]
    var indices: [UInt32]
}

private struct AnchorSnapshot {
    let transform: simd_float4x4
    let positions: [SIMD3<Float>]
    let indices: [UInt32]

    init(_ anchor: ARMeshAnchor) {
        transform = anchor.transform
        let geom = anchor.geometry

        let vBuf = geom.vertices.buffer.contents().advanced(by: geom.vertices.offset)
        let vStride = geom.vertices.stride
        var pos = [SIMD3<Float>](repeating: .zero, count: geom.vertices.count)
        for i in 0..<geom.vertices.count {
            pos[i] = vBuf.advanced(by: i * vStride).load(as: SIMD3<Float>.self)
        }
        positions = pos

        let iBuf = geom.faces.buffer.contents().advanced(by: geom.faces.offset)
        let bytesPerIdx = geom.faces.bytesPerIndex
        let total = geom.faces.count * geom.faces.indexCountPerPrimitive
        var idx = [UInt32](repeating: 0, count: total)
        for i in 0..<total {
            idx[i] = bytesPerIdx == 4
                ? iBuf.advanced(by: i * 4).load(as: UInt32.self)
                : UInt32(iBuf.advanced(by: i * 2).load(as: UInt16.self))
        }
        indices = idx
    }
}

// MARK: - Coordinator

@MainActor
final class MeshScanCoordinator: NSObject, ObservableObject {
    @Published var instruction = "Skieruj aparat na ściany i powoli skanuj pokój"
    @Published var isReady = false
    @Published var framesCaptured = 0
    @Published var buildProgress: Double? = nil
    @Published var meshData: ColoredMeshData? = nil

    weak var arView: ARSCNView?
    private var frames: [RawCameraFrame] = []
    private var lastCaptureTime: TimeInterval = 0
    private let captureInterval: TimeInterval = 1.0
    private let maxFrames = 20

    func start(_ view: ARSCNView) {
        arView = view
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func onFrame(_ frame: ARFrame) {
        if case .normal = frame.camera.trackingState { isReady = true }

        let t = frame.timestamp
        guard t - lastCaptureTime >= captureInterval, frames.count < maxFrames else { return }
        lastCaptureTime = t

        let pb = frame.capturedImage
        frames.append(RawCameraFrame(
            viewMatrix: simd_inverse(frame.camera.transform),
            intrinsics: frame.camera.intrinsics,
            colorBuffer: pb,
            pixelWidth: CVPixelBufferGetWidth(pb),
            pixelHeight: CVPixelBufferGetHeight(pb)
        ))
        framesCaptured = frames.count
    }

    func finish() {
        guard let view = arView,
              let arFrame = view.session.currentFrame else { return }

        let snapshots = arFrame.anchors.compactMap { $0 as? ARMeshAnchor }.map(AnchorSnapshot.init)
        guard !snapshots.isEmpty else { return }

        let capturedFrames = frames
        view.session.pause()
        buildProgress = 0.0

        Task.detached { [weak self] in
            var allPos: [SIMD3<Float>] = []
            var allIdx: [UInt32] = []

            for snap in snapshots {
                let offset = UInt32(allPos.count)
                for local in snap.positions {
                    let w = snap.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                    allPos.append(SIMD3<Float>(w.x, w.y, w.z))
                }
                allIdx.append(contentsOf: snap.indices.map { $0 + offset })
            }

            var allColors = [SIMD3<Float>]()
            allColors.reserveCapacity(allPos.count)
            let total = allPos.count

            for (i, pos) in allPos.enumerated() {
                allColors.append(Self.colorForVertex(pos, frames: capturedFrames))
                if i % 4000 == 0 {
                    let p = Double(i) / Double(max(total, 1))
                    await MainActor.run { self?.buildProgress = p }
                }
            }

            let result = ColoredMeshData(positions: allPos, colors: allColors, indices: allIdx)
            await MainActor.run {
                self?.meshData = result
                self?.buildProgress = nil
            }
        }
    }

    // MARK: vertex coloring (nonisolated — runs on background)

    private static func colorForVertex(_ worldPos: SIMD3<Float>, frames: [RawCameraFrame]) -> SIMD3<Float> {
        var bestColor = SIMD3<Float>(0.45, 0.45, 0.45)
        var bestDepth: Float = .infinity
        let w4 = SIMD4<Float>(worldPos.x, worldPos.y, worldPos.z, 1)

        for frame in frames {
            let cam = frame.viewMatrix * w4
            let depth = -cam.z                     // positive = in front of camera
            guard depth > 0.1, depth < 12.0, depth < bestDepth else { continue }

            let k = frame.intrinsics
            let u = k[0][0] * cam.x / depth + k[2][0]
            let v = k[1][1] * (-cam.y) / depth + k[2][1]

            let ui = Int(u), vi = Int(v)
            guard ui >= 0, ui < frame.pixelWidth - 1,
                  vi >= 0, vi < frame.pixelHeight - 1 else { continue }

            if let c = sampleYCbCr(frame.colorBuffer, col: ui, row: vi) {
                bestColor = c
                bestDepth = depth
            }
        }
        return bestColor
    }

    private static func sampleYCbCr(_ pb: CVPixelBuffer, col: Int, row: Int) -> SIMD3<Float>? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pb) >= 2 else { return nil }
        guard let yBase   = CVPixelBufferGetBaseAddressOfPlane(pb, 0),
              let cbcrBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return nil }

        let yStride   = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let cbcrStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)

        let y    = Float(yBase.assumingMemoryBound(to: UInt8.self)[row * yStride + col])
        let cbOff = (row / 2) * cbcrStride + (col / 2) * 2
        let cb   = Float(cbcrBase.assumingMemoryBound(to: UInt8.self)[cbOff])
        let cr   = Float(cbcrBase.assumingMemoryBound(to: UInt8.self)[cbOff + 1])

        // BT.601 YCbCr → RGB
        let yf = y - 16; let cbf = cb - 128; let crf = cr - 128
        let r = min(max((1.164 * yf + 1.596 * crf) / 255, 0), 1)
        let g = min(max((1.164 * yf - 0.392 * cbf - 0.813 * crf) / 255, 0), 1)
        let b = min(max((1.164 * yf + 2.017 * cbf) / 255, 0), 1)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }
}
