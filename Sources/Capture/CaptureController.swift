import ARKit
import AVFoundation
import CoreImage
import ImageIO
import UIKit

@MainActor
final class CaptureController: NSObject, ObservableObject {
    private var session: ARSession?
    private let ciContext = CIContext()
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
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        session.run(config)
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
        guard let _ = try? device.lockForConfiguration() else { return }
        defer { device.unlockForConfiguration() }
        let maxF = min(device.activeFormat.videoMaxZoomFactor, 5.0)
        device.videoZoomFactor = min(max(factor, device.minAvailableVideoZoomFactor), maxF)
    }

    func snap() -> CapturedShot? {
        guard let frame = session?.currentFrame,
              let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth,
              let confidence = sceneDepth.confidenceMap,
              let depth = DepthExtraction.depthMap(depth: sceneDepth.depthMap, confidence: confidence),
              let jpeg = ciContext.jpegRepresentation(
                of: CIImage(cvPixelBuffer: frame.capturedImage),
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92])
        else { return nil }

        let k = frame.camera.intrinsics
        let res = frame.camera.imageResolution
        let intrinsics = CameraIntrinsics(fx: Double(k[0][0]), fy: Double(k[1][1]),
                                          cx: Double(k[2][0]), cy: Double(k[2][1]),
                                          imageWidth: Int(res.width), imageHeight: Int(res.height))
        let orientation = SensorGeometry.imageOrientation(for: UIDevice.current.orientation)
        return CapturedShot(jpeg: jpeg, depth: depth, intrinsics: intrinsics, orientation: orientation)
    }
}

extension CaptureController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Re-apply zoom every 15 frames so ARKit can't reset it
        guard frame.timestamp.truncatingRemainder(dividingBy: 0.5) < 0.017 else { return }
        Task { @MainActor in
            if self.currentZoom > 1.01 { self.applyZoom(self.currentZoom) }
        }
    }
}
