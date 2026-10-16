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
        .task { load() }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
    }

    private func load() {
        guard let meta = store.list().first(where: { $0.id == id }),
              let depth = store.loadDepth(meta),
              let image = ShotImage.load(meta, store: store) else { state = .failed; return }
        state = .ready(MeasureViewModel(meta: meta, depth: depth, store: store), image)
    }

    private func export(_ vm: MeasureViewModel, _ image: UIImage) {
        let lines = OverlayRenderer.lines(for: vm.meta, depth: vm.depth, displayedSize: image.size)
        guard let data = OverlayRenderer.render(image: image, lines: lines, title: vm.meta.name) else { return }
        let safe = vm.meta.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "pomiar" : safe).jpg")
        try? data.write(to: url, options: .atomic)
        shareItem = ShareItem(url: url)
    }
}
