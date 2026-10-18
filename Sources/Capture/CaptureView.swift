import SwiftUI
import ARKit
import RealityKit

struct CaptureView: View {
    let onCancel: () -> Void
    let onCaptured: (CapturedShot) -> Void

    @StateObject private var controller = CaptureController()
    @State private var failed = false
    @State private var zoomFactor: CGFloat = 1.0

    var body: some View {
        ZStack {
            if CaptureController.isSupported {
                ARCameraView(controller: controller)
                    .scaleEffect(zoomFactor)
                    .ignoresSafeArea()
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
                    HStack(spacing: 8) {
                        Image(systemName: "minus.magnifyingglass").foregroundStyle(.white)
                        Slider(value: $zoomFactor, in: 1.0...5.0)
                            .onChange(of: zoomFactor) { _, v in controller.setZoom(v) }
                        Image(systemName: "plus.magnifyingglass").foregroundStyle(.white)
                        Text(String(format: "%.1f×", zoomFactor))
                            .font(.caption.monospacedDigit()).foregroundStyle(.white).frame(width: 36)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    Button(action: shoot) {
                        Circle().strokeBorder(.white, lineWidth: 4)
                            .background(Circle().fill(.white.opacity(0.85)).padding(6))
                            .frame(width: 76, height: 76)
                    }
                    .padding(.bottom, 28)
                    .padding(.top, 8)
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
        if let shot = controller.snap(zoom: zoomFactor) {
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
