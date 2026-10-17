import RoomPlan
import SwiftUI

@MainActor
final class RoomScanCoordinator: NSObject, ObservableObject {
    @Published var instruction: String = ""
    @Published var capturedData: CapturedRoomData?
    @Published var isScanning = false
    @Published var scanError: String?

    weak var captureView: RoomCaptureView?

    func start() {
        guard let captureView else { return }
        captureView.captureSession.delegate = self
        let config = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: config)
        isScanning = true
    }

    func stop() {
        captureView?.captureSession.stop(pauseARSession: false)
        isScanning = false
    }
}

extension RoomScanCoordinator: RoomCaptureSessionDelegate {
    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didEndWith data: CapturedRoomData, error: Error?) {
        Task { @MainActor in
            if let error {
                self.scanError = error.localizedDescription
            } else {
                self.capturedData = data
            }
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didProvide instruction: RoomCaptureSession.Instruction) {
        let text: String
        switch instruction {
        case .moveCloseToWall:       text = "Podejdź bliżej ściany"
        case .moveAwayFromObstacle:  text = "Odsuń się od przeszkody"
        case .turnOnLight:           text = "Włącz światło"
        case .lowTexture:            text = "Za mało szczegółów — zmień kąt"
        case .normal:                text = ""
        @unknown default:            text = ""
        }
        Task { @MainActor in self.instruction = text }
    }
}
