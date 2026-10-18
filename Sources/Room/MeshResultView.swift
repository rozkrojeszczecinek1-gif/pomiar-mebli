import SwiftUI
import SceneKit

struct MeshResultView: View {
    let data: ColoredMeshData
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MeshSceneView(data: data).ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        onDone()
                    } label: {
                        Label("Gotowe", systemImage: "checkmark")
                            .padding(10).background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    Text("Skan 3D")
                        .font(.headline)
                        .padding(10).background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Color.clear.frame(width: 80)
                }.padding()
                Spacer()
                Text("Obróć palcem  •  Szczypaj = zoom")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(8).background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 20)
            }
        }
        .statusBar(hidden: true)
    }
}

// MARK: - SceneKit view

private struct MeshSceneView: UIViewRepresentable {
    let data: ColoredMeshData

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)

        let scene = SCNScene()

        if let meshNode = buildMeshNode() {
            scene.rootNode.addChildNode(meshNode)

            // Position camera so the whole mesh fits in view
            let (bMin, bMax) = meshNode.boundingBox
            let center = SCNVector3(
                (bMin.x + bMax.x) * 0.5,
                (bMin.y + bMax.y) * 0.5,
                (bMin.z + bMax.z) * 0.5
            )
            let span = max(bMax.x - bMin.x, bMax.y - bMin.y, bMax.z - bMin.z)
            let camDist = span * 1.5

            let camNode = SCNNode()
            camNode.camera = SCNCamera()
            camNode.camera?.zFar = 100
            camNode.position = SCNVector3(center.x, center.y + span * 0.3, center.z + camDist)
            camNode.look(at: center)
            scene.rootNode.addChildNode(camNode)
            view.pointOfView = camNode
        }

        // Ambient light — constant material doesn't need directional, but subtle ambient looks better
        let ambNode = SCNNode()
        ambNode.light = SCNLight()
        ambNode.light?.type = .ambient
        ambNode.light?.intensity = 800
        scene.rootNode.addChildNode(ambNode)

        view.scene = scene
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: geometry builder

    private func buildMeshNode() -> SCNNode? {
        let vertexCount = data.positions.count
        guard vertexCount > 0, data.indices.count >= 3 else { return nil }

        // Flatten positions to packed Float triplets (avoids SIMD3 stride=16 padding issue)
        var posFlat = [Float](); posFlat.reserveCapacity(vertexCount * 3)
        for p in data.positions { posFlat += [p.x, p.y, p.z] }
        let posData = Data(bytes: posFlat, count: posFlat.count * 4)
        let posSource = SCNGeometrySource(
            data: posData, semantic: .vertex, vectorCount: vertexCount,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )

        // Flatten colors to packed RGBA Float quadruplets
        var colorFlat = [Float](); colorFlat.reserveCapacity(vertexCount * 4)
        for c in data.colors { colorFlat += [c.x, c.y, c.z, 1.0] }
        let colorData = Data(bytes: colorFlat, count: colorFlat.count * 4)
        let colorSource = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: vertexCount,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 16
        )

        // Face indices: UInt32 = 4 bytes each
        var idxArr = data.indices
        let idxData = Data(bytes: &idxArr, count: idxArr.count * 4)
        let element = SCNGeometryElement(
            data: idxData, primitiveType: .triangles,
            primitiveCount: data.indices.count / 3,
            bytesPerIndex: 4
        )

        let geom = SCNGeometry(sources: [posSource, colorSource], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        geom.firstMaterial = mat

        return SCNNode(geometry: geom)
    }
}
