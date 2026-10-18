import ARKit
import CoreImage
import ImageIO
import UIKit

@MainActor
final class CaptureController: NSObject, ObservableObject {
    private var session: ARSession?
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                                .outputColorSpace:  CGColorSpace(name: CGColorSpace.displayP3)!])
    private(set) var currentZoom: CGFloat = 1.0

    nonisolated static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    func start(session: ARSession) {
        guard Self.isSupported else { return }
        self.session = session
        session.delegate = self
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        let config = ARWorldTrackingConfiguration()
        config.videoFormat = Self.bestVideoFormat() ?? config.videoFormat
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        session.run(config)
    }

    private static func bestVideoFormat() -> ARWorldTrackingConfiguration.VideoFormat? {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else { return nil }
        return ARWorldTrackingConfiguration.supportedVideoFormats
            .max {
                let a = $0.imageResolution; let b = $1.imageResolution
                return (a.width * a.height) < (b.width * b.height)
            }
    }

    func stop() {
        session?.pause()
        session?.delegate = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func setZoom(_ factor: CGFloat) {
        currentZoom = factor
    }

    func snap(zoom: CGFloat = 1.0) -> CapturedShot? {
        guard let frame = session?.currentFrame,
              let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth,
              let confidence = sceneDepth.confidenceMap,
              let rawDepth = DepthExtraction.depthMap(depth: sceneDepth.depthMap, confidence: confidence)
        else { return nil }

        let rawCI = CIImage(cvPixelBuffer: frame.capturedImage)

        // Crop center of image and depth map to match the visual zoom shown to user
        let ci = zoom > 1.01 ? cropCI(rawCI, zoom: zoom) : rawCI
        let depth = zoom > 1.01 ? cropDepth(rawDepth, zoom: zoom) : rawDepth

        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let imageData: Data?
        if #available(iOS 15, *) {
            imageData = ciContext.heifRepresentation(of: ci,
                                                     format: .RGBAh,
                                                     colorSpace: p3,
                                                     options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0])
        } else {
            imageData = ciContext.jpegRepresentation(of: ci, colorSpace: p3,
                                                     options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.99])
        }
        guard let data = imageData else { return nil }

        let k = frame.camera.intrinsics
        let res = frame.camera.imageResolution
        let rawIntrinsics = CameraIntrinsics(fx: Double(k[0][0]), fy: Double(k[1][1]),
                                             cx: Double(k[2][0]), cy: Double(k[2][1]),
                                             imageWidth: Int(res.width), imageHeight: Int(res.height))
        let intrinsics = zoom > 1.01 ? cropIntrinsics(rawIntrinsics, zoom: zoom) : rawIntrinsics
        let orientation = SensorGeometry.imageOrientation(for: UIDevice.current.orientation)
        return CapturedShot(jpeg: data, depth: depth, intrinsics: intrinsics, orientation: orientation)
    }

    // MARK: - Zoom crop helpers

    private func cropCI(_ ci: CIImage, zoom: CGFloat) -> CIImage {
        let w = ci.extent.width / zoom
        let h = ci.extent.height / zoom
        let x = (ci.extent.width - w) / 2
        let y = (ci.extent.height - h) / 2
        return ci.cropped(to: CGRect(x: x, y: y, width: w, height: h))
            .transformed(by: CGAffineTransform(translationX: -x, y: -y))
    }

    private func cropDepth(_ map: DepthMap, zoom: CGFloat) -> DepthMap {
        let newW = max(1, Int(Double(map.width) / Double(zoom)))
        let newH = max(1, Int(Double(map.height) / Double(zoom)))
        let x0 = (map.width - newW) / 2
        let y0 = (map.height - newH) / 2
        var d = [Float](repeating: 0, count: newW * newH)
        var c = [UInt8](repeating: 0, count: newW * newH)
        for y in 0..<newH {
            for x in 0..<newW {
                let src = (y0 + y) * map.width + (x0 + x)
                let dst = y * newW + x
                d[dst] = map.depth[src]
                c[dst] = map.confidence[src]
            }
        }
        return DepthMap(width: newW, height: newH, depth: d, confidence: c)
    }

    // Adjust intrinsics for a center crop at the given zoom factor.
    // fx/fy stay unchanged (same physical pixel size); cx/cy shift toward center.
    private func cropIntrinsics(_ k: CameraIntrinsics, zoom: CGFloat) -> CameraIntrinsics {
        let newW = Double(k.imageWidth) / Double(zoom)
        let newH = Double(k.imageHeight) / Double(zoom)
        let offsetX = (Double(k.imageWidth) - newW) / 2
        let offsetY = (Double(k.imageHeight) - newH) / 2
        return CameraIntrinsics(fx: k.fx, fy: k.fy,
                                cx: k.cx - offsetX, cy: k.cy - offsetY,
                                imageWidth: Int(newW), imageHeight: Int(newH))
    }
}

extension CaptureController: ARSessionDelegate {}
