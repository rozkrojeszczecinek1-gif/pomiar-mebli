import SwiftUI

struct RootView: View {
    let store: ShotStore
    @State private var path: [UUID] = []
    @State private var showCapture = false

    init(store: ShotStore = ShotStore(root: ShotStore.defaultRoot())) {
        self.store = store
    }

    var body: some View {
        NavigationStack(path: $path) {
            GalleryView(store: store, onNew: { showCapture = true }, onOpen: { path.append($0) })
                .navigationDestination(for: UUID.self) { ShotScreen(store: store, id: $0) }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureView(onCancel: { showCapture = false }, onCaptured: { shot in
                showCapture = false
                let f = DateFormatter()
                f.locale = Locale(identifier: "pl_PL"); f.dateFormat = "yyyy-MM-dd HH:mm"
                if let meta = try? store.save(shot, name: "Pomiar \(f.string(from: Date()))") {
                    path.append(meta.id)
                }
            })
        }
    }
}
