import SwiftUI
import ARKit
import SceneKit

struct MeshScanView: View {
    let onCancel: () -> Void
    let onCompleted: (ColoredMeshData) -> Void

    @StateObject private var coordinator = MeshScanCoordinator()

    var body: some View {
        ZStack {
            MeshARSceneView(coordinator: coordinator).ignoresSafeArea()

            VStack {
                HStack {
                    Button("Anuluj") {
                        coordinator.arView?.session.pause()
                        onCancel()
                    }
                    .padding(10).background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(coordinator.isReady ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(coordinator.isReady ? "Gotowy" : "Inicjalizacja…")
                            .font(.caption)
                    }
                    .padding(8).background(.ultraThinMaterial, in: Capsule())
                }.padding()

                Spacer()

                if !coordinator.instruction.isEmpty {
                    Text(coordinator.instruction)
                        .font(.subheadline).multilineTextAlignment(.center)
                        .padding(10).background(.ultraThinMaterial, in: Capsule())
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                if let progress = coordinator.buildProgress {
                    VStack(spacing: 10) {
                        ProgressView("Kolorowanie siatki 3D…", value: progress, total: 1.0)
                            .padding(.horizontal)
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32).padding(.bottom, 28)
                } else if coordinator.meshData == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "cube.transparent").font(.title3)
                        Text("\(coordinator.framesCaptured) / 20 klatek")
                            .font(.caption.monospacedDigit())
                    }
                    .padding(10).background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 6)

                    Button {
                        coordinator.finish()
                    } label: {
                        Label("Zakończ skanowanie", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 24).padding(.vertical, 14)
                            .background(coordinator.isReady ? Color.green : Color.gray, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .disabled(!coordinator.isReady)
                    .padding(.bottom, 28)
                }
            }
        }
        .onChange(of: coordinator.meshData) { _, data in
            if let data { onCompleted(data) }
        }
        .statusBar(hidden: true)
    }
}

// MARK: - AR view wrapper

private struct MeshARSceneView: UIViewRepresentable {
    @ObservedObject var coordinator: MeshScanCoordinator

    func makeCoordinator() -> Coord { Coord(c: coordinator) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        coordinator.start(view)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coord) {
        uiView.session.pause()
    }

    final class Coord: NSObject, ARSessionDelegate {
        let c: MeshScanCoordinator
        init(c: MeshScanCoordinator) { self.c = c }

        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task { @MainActor in self.c.onFrame(frame) }
        }
    }
}
