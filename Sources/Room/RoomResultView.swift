import SwiftUI
import RoomPlan
import SceneKit
import QuickLook
import simd

struct RoomResultView: View {
    let data: CapturedRoomData
    let onDone: () -> Void

    @State private var room: CapturedRoom?
    @State private var elements: [RoomElement] = []
    @State private var usdzURL: URL?
    @State private var processing = true
    @State private var tab = 0
    @State private var selected: RoomElement?
    @State private var showShare = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if processing {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Budowanie modelu 3D…").foregroundStyle(.secondary)
                    }
                } else if room != nil {
                    VStack(spacing: 0) {
                        Picker("", selection: $tab) {
                            Text("Widok 3D").tag(0)
                            Text("Wymiary").tag(1)
                        }
                        .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)

                        if tab == 0 {
                            scene3D
                        } else {
                            listView
                        }
                    }
                } else {
                    ContentUnavailableView("Brak danych skanu", systemImage: "cube.transparent")
                }
            }
            .navigationTitle("Wynik skanowania")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Gotowe", action: onDone) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                        .disabled(usdzURL == nil)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = usdzURL { ShareSheet(items: [url]) }
        }
        .alert("Błąd", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
            Button("OK") { errorMsg = nil }
        } message: { Text(errorMsg ?? "") }
        .task { await buildRoom() }
    }

    // MARK: - 3D

    private var scene3D: some View {
        ZStack(alignment: .bottom) {
            if let url = usdzURL {
                QuickLookUSDZView(url: url)
                    .ignoresSafeArea(edges: .bottom)
            }
            legend
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip("Ściana", .systemGray)
                chip("Drzwi", .brown)
                chip("Okno", .systemCyan)
                chip("Przejście", .systemGreen)
                chip("Obiekt", .systemOrange)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }

    private func chip(_ label: String, _ color: UIColor) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(Color(color)).frame(width: 14, height: 14)
            Text(label).font(.caption2)
        }
    }

    @ViewBuilder
    private func selectionCard(_ el: RoomElement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: el.kind.icon).foregroundStyle(Color(el.kind.uiColor))
                Text(el.label).font(.headline)
                Spacer()
                Button { withAnimation { selected = nil } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                dimBadge("Szerokość", el.dimensions.x)
                dimBadge("Wysokość", el.dimensions.y)
                dimBadge("Głębokość", el.dimensions.z)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14).padding(.bottom, 28)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func dimBadge(_ label: String, _ meters: Float) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int((Double(meters)*1000).rounded())) mm")
                .font(.caption.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Lista

    private var listView: some View {
        List {
            let grouped = Dictionary(grouping: elements, by: \.kind)
            ForEach([RoomElement.Kind.wall, .door, .window, .opening, .object, .floor], id: \.self) { kind in
                if let items = grouped[kind], !items.isEmpty {
                    Section(kind.title) {
                        ForEach(items) { el in
                            HStack {
                                Image(systemName: el.kind.icon).foregroundStyle(Color(el.kind.uiColor)).frame(width: 24)
                                Text(el.label)
                                Spacer()
                                Text(el.dimLabel)
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - build

    private func buildRoom() async {
        do {
            let builder = RoomBuilder(options: [.beautifyObjects])
            let captured = try await builder.capturedRoom(from: data)
            let els = RoomElement.from(captured)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pokoj-\(Int(Date().timeIntervalSince1970)).usdz")
            try captured.export(to: url)
            await MainActor.run {
                room = captured; elements = els; usdzURL = url; processing = false
            }
        } catch {
            await MainActor.run { errorMsg = error.localizedDescription; processing = false }
        }
    }
}

// MARK: - QuickLook USDZ viewer (proper PBR rendering + AR placement)

private struct QuickLookUSDZView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

// MARK: - USDZ + element overlay in SCNView (kept for fallback reference)

private struct USDZSceneView: UIViewRepresentable {
    let usdzURL: URL
    let elements: [RoomElement]
    let selected: RoomElement?
    let onSelect: (RoomElement?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(elements: elements, onSelect: onSelect) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = UIColor.systemGroupedBackground

        // Load the USDZ (realistic geometry from RoomPlan)
        if let scene = try? SCNScene(url: usdzURL, options: nil) {
            view.scene = scene
        } else {
            // fallback: colored boxes
            let scene = SCNScene()
            context.coordinator.buildBoxScene(into: scene)
            view.scene = scene
        }
        addLighting(to: view.scene!)
        context.coordinator.buildOverlayNodes(in: view.scene!)
        context.coordinator.positionCamera(in: view)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.scnView = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.updateSelection(selected)
    }

    private func addLighting(to scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = { let l = SCNLight(); l.type = .ambient; l.intensity = 500; return l }()
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = { let l = SCNLight(); l.type = .directional; l.intensity = 800; return l }()
        sun.eulerAngles = SCNVector3(-Float.pi/4, Float.pi/4, 0)
        scene.rootNode.addChildNode(sun)
    }

    final class Coordinator: NSObject {
        let elements: [RoomElement]
        let onSelect: (RoomElement?) -> Void
        var elementNodes: [(SCNNode, RoomElement)] = []
        weak var scnView: SCNView?

        init(elements: [RoomElement], onSelect: @escaping (RoomElement?) -> Void) {
            self.elements = elements; self.onSelect = onSelect
        }

        // Transparent hit-test overlay nodes (invisible boxes on top of USDZ)
        func buildOverlayNodes(in scene: SCNScene) {
            for el in elements {
                let d = el.dimensions
                let box = SCNBox(width: CGFloat(max(d.x, 0.01)),
                                 height: CGFloat(max(d.y, 0.01)),
                                 length: CGFloat(max(d.z, 0.01)),
                                 chamferRadius: 0)
                let mat = SCNMaterial()
                mat.diffuse.contents = UIColor.clear
                mat.isDoubleSided = true
                box.firstMaterial = mat
                let node = SCNNode(geometry: box)
                node.simdTransform = el.transform
                node.opacity = 0.001  // nearly invisible but hittable
                scene.rootNode.addChildNode(node)
                elementNodes.append((node, el))
            }
        }

        // Fallback box scene (when USDZ fails)
        func buildBoxScene(into scene: SCNScene) {
            for el in elements {
                let d = el.dimensions
                let box = SCNBox(width: CGFloat(max(d.x, 0.01)),
                                 height: CGFloat(max(d.y, 0.01)),
                                 length: CGFloat(max(d.z, 0.01)),
                                 chamferRadius: 0.005)
                let mat = SCNMaterial()
                mat.diffuse.contents = el.kind.uiColor.withAlphaComponent(0.85)
                mat.isDoubleSided = true
                box.firstMaterial = mat
                let node = SCNNode(geometry: box)
                node.simdTransform = el.transform
                scene.rootNode.addChildNode(node)
                elementNodes.append((node, el))
            }
        }

        func positionCamera(in view: SCNView) {
            guard !elements.isEmpty else { return }
            var minX: Float = .greatestFiniteMagnitude, maxX: Float = -.greatestFiniteMagnitude
            var minZ: Float = .greatestFiniteMagnitude, maxZ: Float = -.greatestFiniteMagnitude
            for el in elements {
                let p = el.transform.columns.3
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
            }
            let cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2
            let span = max(maxX - minX, maxZ - minZ, 3)
            let cam = SCNNode()
            cam.camera = { let c = SCNCamera(); c.fieldOfView = 55; c.zFar = 100; return c }()
            cam.position = SCNVector3(cx, span * 0.8, cz + span * 1.2)
            cam.look(at: SCNVector3(cx, 0, cz))
            view.scene?.rootNode.addChildNode(cam)
            view.pointOfView = cam
        }

        func updateSelection(_ selected: RoomElement?) {
            for (node, el) in elementNodes {
                let mat = node.geometry?.firstMaterial
                let isSelected = selected?.id == el.id
                // make selected element glow; deselected goes back to near-invisible
                node.opacity = isSelected ? 0.35 : 0.001
                mat?.emission.contents = isSelected ? el.kind.uiColor.withAlphaComponent(0.6) : UIColor.black
            }
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let pt = g.location(in: view)
            let hits = view.hitTest(pt, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
            let tapped = hits.compactMap { h -> RoomElement? in
                elementNodes.first(where: { $0.0 === h.node })?.1
            }.first
            onSelect(tapped)
        }
    }
}

// MARK: - RoomElement.Kind extensions

extension RoomElement.Kind {
    var title: String {
        switch self { case .wall: "Ściany"; case .door: "Drzwi"; case .window: "Okna"
        case .opening: "Przejścia"; case .object: "Obiekty"; case .floor: "Podłogi" }
    }
    var icon: String {
        switch self { case .wall: "rectangle.fill"; case .door: "door.left.hand.open"
        case .window: "window.horizontal"; case .opening: "arrow.left.and.right"
        case .object: "cube.fill"; case .floor: "square.fill" }
    }
    var uiColor: UIColor {
        switch self { case .wall: .systemGray; case .door: .brown; case .window: .systemCyan
        case .opening: .systemGreen; case .object: .systemOrange; case .floor: .systemGray2 }
    }
}
