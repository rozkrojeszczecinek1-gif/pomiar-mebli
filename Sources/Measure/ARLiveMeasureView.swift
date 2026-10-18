import SwiftUI
import ARKit
import SceneKit

// MARK: - Entry point

struct ARLiveMeasureView: View {
    let store: ShotStore
    let projectName: String
    let onDone: () -> Void

    @StateObject private var vm = ARLiveMeasureVM()

    var body: some View {
        ZStack {
            ARMeasureSceneView(vm: vm).ignoresSafeArea()

            // Crosshair + live depth at screen center
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5).frame(width: 44, height: 44)
                        Rectangle().fill(.white.opacity(0.9)).frame(width: 20, height: 1.5)
                        Rectangle().fill(.white.opacity(0.9)).frame(width: 1.5, height: 20)
                        if !vm.liveDepthLabel.isEmpty {
                            Text(vm.liveDepthLabel)
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.black.opacity(0.5), in: Capsule())
                                .offset(y: 30)
                        }
                    }
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Button("Zamknij") { onDone() }
                        .padding(10).background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    trackingBadge
                }.padding()

                Spacer()

                if !vm.hint.isEmpty {
                    Text(vm.hint)
                        .font(.subheadline)
                        .padding(10).background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 4)
                }

                if !vm.measurements.isEmpty {
                    measurementStrip
                }

                bottomBar
            }
        }
        .statusBar(hidden: true)
    }

    @ViewBuilder
    private var trackingBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.trackingColor)
                .frame(width: 8, height: 8)
            Text(vm.trackingLabel)
                .font(.caption)
        }
        .padding(8).background(.ultraThinMaterial, in: Capsule())
    }

    private var measurementStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.measurements) { m in
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(m.label).font(.caption.monospacedDigit()).bold()
                        Button { vm.delete(m) } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }.padding(.horizontal, 14)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            if vm.pointA != nil {
                Button("Cofnij A") { vm.cancelPoint() }
                    .padding(12).background(.ultraThinMaterial, in: Capsule())
            }
            Button {
                vm.save(to: store)
                onDone()
            } label: {
                Label("Zapisz (\(vm.measurements.count))", systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(vm.measurements.isEmpty ? Color.gray : Color.green, in: Capsule())
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .disabled(vm.measurements.isEmpty)
        }
        .padding(.bottom, 28)
    }
}

// MARK: - ViewModel

@MainActor
final class ARLiveMeasureVM: NSObject, ObservableObject {

    struct LiveMeasurement: Identifiable {
        let id = UUID()
        let a: SCNVector3
        let b: SCNVector3
        let nodeA: SCNNode
        let nodeB: SCNNode
        let lineNode: SCNNode
        let labelNode: SCNNode
        var distanceM: Float { SCNVector3Distance(a, b) }
        var label: String { "\(Int((Double(distanceM) * 1000).rounded())) mm" }
    }

    @Published var measurements: [LiveMeasurement] = []
    @Published var hint = "Skieruj na powierzchnię i dotknij punkt A"
    @Published var trackingLabel = "Inicjalizacja…"
    @Published var trackingColor = Color.orange
    @Published var liveDepthLabel = ""

    var pointA: SCNVector3?
    private var nodeA: SCNNode?
    weak var scnView: ARSCNView?

    func handleTap(at screenPoint: CGPoint) {
        guard let view = scnView,
              let frame = view.session.currentFrame,
              let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            hint = "Brak danych głębi — poczekaj chwilę"
            return
        }
        let vs = view.bounds.size
        guard vs.width > 0, vs.height > 0 else { return }

        // Portrait screen → landscape sensor (toSensor .right: nx=sy/H, ny=1-sx/W)
        let nx = screenPoint.y / vs.height
        let ny = 1.0 - screenPoint.x / vs.width

        // Sample LiDAR depth (Float32 CVPixelBuffer, landscape 256×192)
        let pb = sceneDepth.depthMap
        let dW = CVPixelBufferGetWidth(pb), dH = CVPixelBufferGetHeight(pb)
        let dCol = min(max(Int(nx * Double(dW)), 0), dW - 1)
        let dRow = min(max(Int(ny * Double(dH)), 0), dH - 1)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: Float32.self)
        let stride = CVPixelBufferGetBytesPerRow(pb) / 4
        let z = Double(base[dRow * stride + dCol])
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)

        guard z.isFinite, z > 0.15, z < 8.0 else {
            hint = "Nie można zmierzyć tutaj — skieruj na bliższą powierzchnię"
            return
        }

        // Back-project to world space using camera intrinsics + transform
        let k = frame.camera.intrinsics
        let res = frame.camera.imageResolution
        let imgCol = nx * Double(res.width)
        let imgRow = ny * Double(res.height)
        let xCV = (imgCol - Double(k[2][0])) / Double(k[0][0]) * z
        let yCV = (imgRow - Double(k[2][1])) / Double(k[1][1]) * z
        // Image: Y down, Z forward → ARKit camera: Y up, Z toward viewer (negative)
        let camPos = SIMD4<Float>(Float(xCV), Float(-yCV), Float(-z), 1)
        let worldPos = frame.camera.transform * camPos
        let pt = SCNVector3(worldPos.x, worldPos.y, worldPos.z)

        if pointA == nil { placeA(pt, scene: view.scene) }
        else             { placeB(pt, scene: view.scene) }
    }

    func updateLiveDepth(frame: ARFrame) {
        guard let sd = frame.smoothedSceneDepth ?? frame.sceneDepth else { liveDepthLabel = ""; return }
        let pb = sd.depthMap
        let dW = CVPixelBufferGetWidth(pb), dH = CVPixelBufferGetHeight(pb)
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: Float32.self)
        let stride = CVPixelBufferGetBytesPerRow(pb) / 4
        let z = Double(base[(dH / 2) * stride + dW / 2])
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        liveDepthLabel = z.isFinite && z > 0 ? String(format: "%.2f m", z) : ""
    }

    private func placeA(_ pt: SCNVector3, scene: SCNScene) {
        nodeA?.removeFromParentNode()
        let n = dotNode(color: .systemYellow, at: pt, radius: 0.009)
        scene.rootNode.addChildNode(n)
        pointA = pt; nodeA = n
        hint = "Teraz dotknij punkt B"
    }

    private func placeB(_ pt: SCNVector3, scene: SCNScene) {
        guard let a = pointA, let nA = nodeA else { return }
        let nB = dotNode(color: .systemGreen, at: pt, radius: 0.009)
        let line = lineNode(from: a, to: pt)
        let lbl = textNode(mm: Int((Double(SCNVector3Distance(a, pt)) * 1000).rounded()),
                           at: midSCN(a, pt))
        for n in [nB, line, lbl] { scene.rootNode.addChildNode(n) }
        measurements.append(LiveMeasurement(a: a, b: pt, nodeA: nA, nodeB: nB, lineNode: line, labelNode: lbl))
        pointA = nil; nodeA = nil
        hint = "Dotknij kolejny punkt A"
    }

    func cancelPoint() {
        nodeA?.removeFromParentNode()
        nodeA = nil; pointA = nil
        hint = "Skieruj na powierzchnię i dotknij punkt A"
    }

    func delete(_ m: LiveMeasurement) {
        [m.nodeA, m.nodeB, m.lineNode, m.labelNode].forEach { $0.removeFromParentNode() }
        measurements.removeAll { $0.id == m.id }
    }

    func save(to store: ShotStore) {
        guard let view = scnView else { return }
        let snap = view.snapshot()
        guard let jpeg = snap.jpegData(compressionQuality: 0.88) else { return }
        let depth = DepthMap.uniform(width: 32, height: 24, depth: 1.0)
        let w = Int(snap.size.width * snap.scale)
        let h = Int(snap.size.height * snap.scale)
        let intrinsics = CameraIntrinsics(fx: Double(w), fy: Double(w),
                                          cx: Double(w)/2, cy: Double(h)/2,
                                          imageWidth: w, imageHeight: h)
        let shot = CapturedShot(jpeg: jpeg, depth: depth, intrinsics: intrinsics, orientation: .up)
        let f = DateFormatter(); f.locale = Locale(identifier: "pl_PL"); f.dateFormat = "yyyy-MM-dd HH:mm"
        _ = try? store.save(shot, name: "AR Live \(f.string(from: Date()))")
    }

    func updateTracking(state: ARCamera.TrackingState) {
        switch state {
        case .normal:
            trackingLabel = "Gotowy"; trackingColor = .green
        case .limited(let reason):
            switch reason {
            case .initializing: trackingLabel = "Inicjalizacja…"; trackingColor = .orange
            case .excessiveMotion: trackingLabel = "Za szybki ruch"; trackingColor = .orange
            case .insufficientFeatures: trackingLabel = "Za mało szczegółów"; trackingColor = .orange
            case .relocalizing: trackingLabel = "Relokalizacja…"; trackingColor = .orange
            @unknown default: trackingLabel = "Ograniczony"; trackingColor = .orange
            }
        case .notAvailable:
            trackingLabel = "Brak śledzenia"; trackingColor = .red
        @unknown default:
            trackingLabel = "…"; trackingColor = .gray
        }
    }

    // MARK: scene geometry helpers

    private func dotNode(color: UIColor, at pos: SCNVector3, radius: CGFloat) -> SCNNode {
        let g = SCNSphere(radius: radius)
        g.firstMaterial?.diffuse.contents = color
        g.firstMaterial?.lightingModel = .constant
        let n = SCNNode(geometry: g); n.position = pos; return n
    }

    private func lineNode(from a: SCNVector3, to b: SCNVector3) -> SCNNode {
        let len = CGFloat(SCNVector3Distance(a, b))
        let cyl = SCNCylinder(radius: 0.003, height: len)
        cyl.firstMaterial?.diffuse.contents = UIColor.white
        cyl.firstMaterial?.lightingModel = .constant
        let n = SCNNode(geometry: cyl)
        n.position = midSCN(a, b)
        n.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        return n
    }

    private func textNode(mm: Int, at pos: SCNVector3) -> SCNNode {
        let text = SCNText(string: "\(mm) mm", extrusionDepth: 0.001)
        text.font = UIFont.boldSystemFont(ofSize: 0.05)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.lightingModel = .constant
        let n = SCNNode(geometry: text)
        let (min, max) = n.boundingBox
        n.pivot = SCNMatrix4MakeTranslation((max.x - min.x) / 2, 0, 0)
        n.position = SCNVector3(pos.x, pos.y + 0.05, pos.z)
        n.constraints = [SCNBillboardConstraint()]
        return n
    }

    private func midSCN(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
    }
}

private func SCNVector3Distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
    let d = SIMD3<Float>(b.x-a.x, b.y-a.y, b.z-a.z)
    return simd_length(d)
}

// MARK: - UIViewRepresentable

private struct ARMeasureSceneView: UIViewRepresentable {
    @ObservedObject var vm: ARLiveMeasureVM

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.autoenablesDefaultLighting = true
        view.automaticallyUpdatesLighting = true

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics = [.smoothedSceneDepth]
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        vm.scnView = view
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let vm: ARLiveMeasureVM
        init(vm: ARLiveMeasureVM) { self.vm = vm }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? ARSCNView else { return }
            Task { @MainActor in self.vm.handleTap(at: g.location(in: v)) }
        }

        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task { @MainActor in
                self.vm.updateTracking(state: frame.camera.trackingState)
                self.vm.updateLiveDepth(frame: frame)
            }
        }
    }
}
