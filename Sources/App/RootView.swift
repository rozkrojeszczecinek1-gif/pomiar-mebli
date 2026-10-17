import SwiftUI
import RoomPlan

struct RootView: View {
    @StateObject private var projectStore = ProjectStore()
    @State private var selectedProject: ProjectMeta?
    @State private var path: [UUID] = []
    @State private var showCapture = false
    @State private var showRoomScan = false
    @State private var showLiveMeasure = false
    @State private var roomScanData: CapturedRoomData?

    private var shotStore: ShotStore? {
        selectedProject.map { projectStore.shotStore(for: $0) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            if let project = selectedProject, let store = shotStore {
                GalleryView(
                    store: store,
                    projectName: project.name,
                    onNew: { showCapture = true },
                    onOpen: { path.append($0) },
                    onRoomScan: { showRoomScan = true },
                    onLiveMeasure: { showLiveMeasure = true }
                )
                .navigationDestination(for: UUID.self) { ShotScreen(store: store, id: $0) }
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            path = []
                            selectedProject = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Projekty")
                            }
                        }
                    }
                }
            } else {
                ProjectListView(store: projectStore, onSelect: { project in
                    selectedProject = project
                    path = []
                })
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            if let store = shotStore {
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
        .fullScreenCover(isPresented: $showLiveMeasure) {
            if let store = shotStore, let project = selectedProject {
                ARLiveMeasureView(store: store, projectName: project.name) {
                    showLiveMeasure = false
                }
            }
        }
    }
}
