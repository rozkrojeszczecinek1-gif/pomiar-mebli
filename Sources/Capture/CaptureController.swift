import ARKit
import AVFoundation
import CoreImage
import ImageIO
import UIKit

@MainActor
final class CaptureController: NSObject, ObservableObject {
    private var session: ARSession?
    // Use 16-bit wide color CIContext for maximum colour fidelity
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                                .outputColorSpace:  CGColorSpace(name: CGColorSpace.displayP3)!])
    private var currentZoom: CGFloat = 1.0

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
        // Pick highest-resolution format available (4K on iPhone 14 Pro Max)
        config.videoFormat = Self.bestVideoFormat() ?? config.videoFormat
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        session.run(config)
    }

    private static func bestVideoFormat() -> ARWorldTrackingConfiguration.VideoFormat? {
        ARWorldTrackingConfiguration.supportedVideoFormats
            .filter { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }
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
        applyZoom(factor)
    }

    private func applyZoom(_ factor: CGFloat) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        do { try device.lockForConfiguration() } catch { return }
        defer { device.unlockForConfiguration() }
        let maxF = min(device.activeFormat.videoMaxZoomFactor, 5.0)
        device.videoZoomFactor = min(max(factor, device.minAvailableVideoZoomFactor), maxF)
    }

    func snap() -> CapturedShot? {
        guard let frame = session?.currentFrame,
              let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth,
              let confidence = sceneDepth.confidenceMap,
              let depth = DepthExtraction.depthMap(depth: sceneDepth.depthMap, confidence: confidence)
        else { return nil }

        let ci = CIImage(cvPixelBuffer: frame.capturedImage)

        // Prefer HEIF 16-bit (P3 wide colour) — closest to ProRAW we can get from ARKit
        // ARKit gives YCbCr CVPixelBuffer; true ProRAW sensor data is not available from ARKit API
        let imageData: Data?
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        if #available(iOS 15, *) {
            imageData = ciContext.heifRepresentation(of: ci,
                                                     format: .RGBAh,   // 16-bit half-precision
                                                     colorSpace: p3,
                                                     options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0])
        } else {
            imageData = ciContext.jpegRepresentation(of: ci, colorSpace: p3,
                                                     options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.99])
        }
        guard let data = imageData else { return nil }

        let k = frame.camera.intrinsics
        let res = frame.camera.imageResolution
        let intrinsics = CameraIntrinsics(fx: Double(k[0][0]), fy: Double(k[1][1]),
                                          cx: Double(k[2][0]), cy: Double(k[2][1]),
                                          imageWidth: Int(res.width), imageHeight: Int(res.height))
        let orientation = SensorGeometry.imageOrientation(for: UIDevice.current.orientation)
        return CapturedShot(jpeg: data, depth: depth, intrinsics: intrinsics, orientation: orientation)
    }
}

extension CaptureController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp.truncatingRemainder(dividingBy: 0.5) < 0.017 else { return }
        Task { @MainActor in
            if self.currentZoom > 1.01 { self.applyZoom(self.currentZoom) }
        }
    }
}
