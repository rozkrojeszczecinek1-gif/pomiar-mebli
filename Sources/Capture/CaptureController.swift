import ARKit
import CoreImage
import ImageIO
import UIKit

@MainActor
final class CaptureController: ObservableObject {
    private var session: ARSession?
    private let ciContext = CIContext()

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    func start(session: ARSession) {
        guard Self.isSupported else { return }
        self.session = session
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth
        session.run(config)
    }

    func stop() {
        session?.pause()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func snap() -> CapturedShot? {
        guard let frame = session?.currentFrame,
              let sceneDepth = frame.sceneDepth,
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
