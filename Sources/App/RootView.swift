import SwiftUI
import RoomPlan

struct RootView: View {
    let store: ShotStore
    @State private var path: [UUID] = []
    @State private var showCapture = false
    @State private var showRoomScan = false
    @State private var roomScanData: CapturedRoomData?

    init(store: ShotStore = ShotStore(root: ShotStore.defaultRoot())) {
        self.store = store
    }

    var body: some View {
        NavigationStack(path: $path) {
            GalleryView(
                store: store,
                onNew: { showCapture = true },
                onOpen: { path.append($0) },
                onRoomScan: { showRoomScan = true }
            )
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
        .fullScreenCover(isPresented: $showRoomScan) {
            if let data = roomScanData {
                RoomResultView(data: data) {
                    roomScanData = nil
                    showRoomScan = false
                }
            } else {
                RoomScanView(
                    onCancel: { showRoomScan = false },
                    onCompleted: { data in roomScanData = data }
                )
            }
        }
    }
}
