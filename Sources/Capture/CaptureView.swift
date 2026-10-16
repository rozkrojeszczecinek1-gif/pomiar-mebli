import SwiftUI
import ARKit
import RealityKit

struct CaptureView: View {
    let onCancel: () -> Void
    let onCaptured: (CapturedShot) -> Void

    @StateObject private var controller = CaptureController()
    @State private var failed = false

    var body: some View {
        ZStack {
            if CaptureController.isSupported {
                ARCameraView(controller: controller).ignoresSafeArea()
                VStack {
                    HStack {
                        Button("Anuluj", action: onCancel)
                            .padding(10).background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }.padding()
                    Spacer()
                    if failed {
                        Text("Nie udało się zapisać klatki z głębią — spróbuj jeszcze raz.")
                            .font(.footnote).padding(8).background(.ultraThinMaterial, in: Capsule())
                    }
                    Button(action: shoot) {
                        Circle().strokeBorder(.white, lineWidth: 4)
                            .background(Circle().fill(.white.opacity(0.85)).padding(6))
                            .frame(width: 76, height: 76)
                    }
                    .padding(.bottom, 28)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("To urządzenie nie ma skanera LiDAR.\nPotrzebny jest iPhone Pro (12 Pro lub nowszy).")
                        .multilineTextAlignment(.center)
                    Button("Wróć", action: onCancel)
                }.padding()
            }
        }
    }

    private func shoot() {
        if let shot = controller.snap() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            controller.stop()
            onCaptured(shot)
        } else {
            failed = true
        }
    }
}

private struct ARCameraView: UIViewRepresentable {
    let controller: CaptureController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        controller.start(session: view.session)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        uiView.session.pause()
    }
}
