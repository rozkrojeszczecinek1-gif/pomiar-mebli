import SwiftUI
import RoomPlan

struct RoomScanView: View {
    let onCancel: () -> Void
    let onCompleted: (CapturedRoomData) -> Void

    @StateObject private var coordinator = RoomScanCoordinator()
    @State private var processing = false

    var body: some View {
        ZStack {
            RoomCaptureRepresentable(coordinator: coordinator)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Button("Anuluj") {
                        coordinator.stop()
                        onCancel()
                    }
                    .padding(10).background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }.padding()
                Spacer()
                if !coordinator.instruction.isEmpty {
                    Text(coordinator.instruction)
                        .font(.subheadline)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
                if processing {
                    ProgressView("Przetwarzanie skanu…")
                        .padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 28)
                } else {
                    Button {
                        processing = true
                        coordinator.stop()
                    } label: {
                        Label("Zakończ skanowanie", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 24).padding(.vertical, 14)
                            .background(.green, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .onReceive(coordinator.$capturedData) { data in
            guard let data else { return }
            onCompleted(data)
        }
        .alert("Błąd skanowania", isPresented: Binding(
            get: { coordinator.scanError != nil },
            set: { if !$0 { coordinator.scanError = nil } }
        )) {
            Button("OK") { coordinator.scanError = nil; onCancel() }
        } message: {
            Text(coordinator.scanError ?? "")
        }
    }
}

private struct RoomCaptureRepresentable: UIViewRepresentable {
    let coordinator: RoomScanCoordinator

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coordinator.captureView = view
        coordinator.start()
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: ()) {
        uiView.captureSession.stop(pauseARSession: false)
    }
}
