import SwiftUI
import ARKit
import RealityKit
import PhotosUI

struct CaptureView: View {
    let onCancel: () -> Void
    let onCaptured: (CapturedShot) -> Void

    @StateObject private var controller = CaptureController()
    @State private var failed = false
    @State private var zoomFactor: CGFloat = 1.0
    @State private var selectedPhoto: PhotosPickerItem? = nil

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
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    HStack(spacing: 20) {
                        // Gallery picker
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .onChange(of: selectedPhoto) { _, item in
                            Task { await importGalleryPhoto(item) }
                        }

                        // Shutter
                        Button(action: shoot) {
                            Circle().strokeBorder(.white, lineWidth: 4)
                                .background(Circle().fill(.white.opacity(0.85)).padding(6))
                                .frame(width: 76, height: 76)
                        }

                        // Spacer for balance
                        Color.clear.frame(width: 56, height: 56)
                    }
                    .padding(.bottom, 28).padding(.top, 8)
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

    @MainActor
    private func importGalleryPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let raw = UIImage(data: data) else { return }

        // Normalise orientation and scale to max 2048px
        let maxSide: CGFloat = 2048
        let scale = min(maxSide / max(raw.size.width, raw.size.height), 1.0)
        let sz = CGSize(width: raw.size.width * scale, height: raw.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: sz)
        let img = renderer.image { _ in raw.draw(in: CGRect(origin: .zero, size: sz)) }
        guard let jpeg = img.jpegData(compressionQuality: 0.92) else { return }

        let w = Int(sz.width), h = Int(sz.height)
        // Uniform depth 0 → measurements will show red, user knows to use manual mode
        let depth = DepthMap.uniform(width: 32, height: 24, depth: 0, confidence: 0)
        let fx = Double(max(w, h)) * 0.88
        let intrinsics = CameraIntrinsics(fx: fx, fy: fx, cx: Double(w) / 2, cy: Double(h) / 2,
                                          imageWidth: w, imageHeight: h)
        let shot = CapturedShot(jpeg: jpeg, depth: depth, intrinsics: intrinsics, orientation: .up)
        controller.stop()
        onCaptured(shot)
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
