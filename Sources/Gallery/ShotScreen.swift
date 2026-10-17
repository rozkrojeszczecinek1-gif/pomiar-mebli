import SwiftUI
import UIKit

enum ShotImage {
    static func load(_ meta: ShotMeta, store: ShotStore) -> UIImage? {
        guard let raw = UIImage(contentsOfFile: store.imageURL(for: meta.id).path),
              let cg = raw.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: meta.orientation.uiOrientation)
    }
}

/// Wczytuje zdjęcie + głębię i pokazuje MeasureView (albo komunikat o błędzie).
struct ShotScreen: View {
    let store: ShotStore
    let id: UUID

    @State private var state: LoadState = .loading
    @State private var shareItem: ShareItem?
    @State private var exportError = false

    private enum LoadState { case loading, failed, ready(MeasureViewModel, UIImage) }
    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        Group {
            switch state {
            case .loading: ProgressView()
            case .failed: Text("Nie można wczytać zdjęcia (brak plików).").foregroundStyle(.secondary)
            case .ready(let vm, let image):
                MeasureView(viewModel: vm, image: image) { export(vm, image) }
            }
        }
        .task { await load() }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .alert("Nie można wyeksportować zdjęcia", isPresented: $exportError) {
            Button("OK") { exportError = false }
        } message: {
            Text("Sprawdź dostępne miejsce na dysku.")
        }
    }

    private func load() async {
        let result: (ShotMeta, DepthMap, UIImage)? = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { [store, id] in
                guard let meta = store.list().first(where: { $0.id == id }),
                      let depth = store.loadDepth(meta),
                      let image = ShotImage.load(meta, store: store) else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: (meta, depth, image))
            }
        }
        if let (meta, depth, image) = result {
            state = .ready(MeasureViewModel(meta: meta, depth: depth, store: store), image)
        } else {
            state = .failed
        }
    }

    private func export(_ vm: MeasureViewModel, _ image: UIImage) {
        let lines = OverlayRenderer.lines(for: vm.meta, depth: vm.depth, displayedSize: image.size)
        guard let data = OverlayRenderer.render(image: image, lines: lines, title: vm.meta.name) else { return }
        let safe = vm.meta.name.replacingOccurrences(of: "/", with: "-")
        let base = safe.isEmpty ? "pomiar" : safe
        let name = "\(base)-\(vm.meta.id.uuidString.prefix(8)).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            exportError = true
        }
    }
}
