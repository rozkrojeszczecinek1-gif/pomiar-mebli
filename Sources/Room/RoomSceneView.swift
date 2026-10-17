import SwiftUI
import SceneKit
import simd

struct RoomSceneView: UIViewRepresentable {
    let elements: [RoomElement]
    let selected: RoomElement?
    let onSelect: (RoomElement?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(elements: elements, onSelect: onSelect) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = UIColor.systemGroupedBackground
        view.defaultCameraController.interactionMode = .orbitTurntable

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.scnView = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.highlight(selected)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let scene = SCNScene()
        let elements: [RoomElement]
        let onSelect: (RoomElement?) -> Void
        var nodeToElement: [ObjectIdentifier: RoomElement] = [:]
        weak var scnView: SCNView?

        init(elements: [RoomElement], onSelect: @escaping (RoomElement?) -> Void) {
            self.elements = elements
            self.onSelect = onSelect
            super.init()
            buildScene()
        }

        private func buildScene() {
            let ambient = SCNNode()
            ambient.light = { let l = SCNLight(); l.type = .ambient; l.intensity = 600; return l }()
            scene.rootNode.addChildNode(ambient)

            let sun = SCNNode()
            sun.light = { let l = SCNLight(); l.type = .directional; l.intensity = 900; return l }()
            sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
            scene.rootNode.addChildNode(sun)

            for element in elements {
                let node = makeNode(element)
                nodeToElement[ObjectIdentifier(node)] = element
                scene.rootNode.addChildNode(node)
            }

            positionCamera()
        }

        private func makeNode(_ el: RoomElement) -> SCNNode {
            let d = el.dimensions
            let w = max(CGFloat(d.x), 0.01)
            let h = max(CGFloat(d.y), 0.01)
            let depth = max(CGFloat(d.z), 0.01)
            let box = SCNBox(width: w, height: h, length: depth, chamferRadius: 0.005)
            let mat = SCNMaterial()
            mat.isDoubleSided = true
            mat.diffuse.contents = baseColor(el.kind)
            box.firstMaterial = mat
            let node = SCNNode(geometry: box)
            node.simdTransform = el.transform
            return node
        }

        private func baseColor(_ kind: RoomElement.Kind) -> UIColor {
            switch kind {
            case .wall:    return UIColor.systemGray.withAlphaComponent(0.85)
            case .door:    return UIColor.brown.withAlphaComponent(0.9)
            case .window:  return UIColor.systemCyan.withAlphaComponent(0.55)
            case .opening: return UIColor.systemGreen.withAlphaComponent(0.45)
            case .object:  return UIColor.systemOrange.withAlphaComponent(0.85)
            case .floor:   return UIColor.systemGray2.withAlphaComponent(0.5)
            }
        }

        func highlight(_ selected: RoomElement?) {
            for (oid, el) in nodeToElement {
                // find node via scene traversal
                scene.rootNode.enumerateChildNodes { node, _ in
                    guard ObjectIdentifier(node) == oid else { return }
                    let mat = node.geometry?.firstMaterial
                    if let s = selected, s.id == el.id {
                        mat?.emission.contents = UIColor.yellow.withAlphaComponent(0.45)
                    } else {
                        mat?.emission.contents = UIColor.black
                    }
                }
            }
        }

        private func positionCamera() {
            var minX: Float = .greatestFiniteMagnitude, maxX: Float = -.greatestFiniteMagnitude
            var minZ: Float = .greatestFiniteMagnitude, maxZ: Float = -.greatestFiniteMagnitude
            for el in elements {
                let px = el.transform.columns.3.x
                let pz = el.transform.columns.3.z
                minX = min(minX, px); maxX = max(maxX, px)
                minZ = min(minZ, pz); maxZ = max(maxZ, pz)
            }
            let cx = (minX + maxX) / 2
            let cz = (minZ + maxZ) / 2
            let span = max(maxX - minX, maxZ - minZ, 3)
            let dist = span * 1.4

            let camNode = SCNNode()
            camNode.camera = {
                let c = SCNCamera(); c.fieldOfView = 55
                c.zFar = 100; return c
            }()
            camNode.position = SCNVector3(cx, dist * 0.7, cz + dist)
            camNode.look(at: SCNVector3(cx, 0, cz))
            scene.rootNode.addChildNode(camNode)
            scnView?.pointOfView = camNode
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let pt = g.location(in: view)
            let hit = view.hitTest(pt, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
            let tapped = hit.first.flatMap { nodeToElement[ObjectIdentifier($0.node)] }
            onSelect(tapped)
        }
    }
}
