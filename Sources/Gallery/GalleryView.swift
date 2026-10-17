import SwiftUI

struct GalleryView: View {
    let store: ShotStore
    let onNew: () -> Void
    let onOpen: (UUID) -> Void
    let onRoomScan: () -> Void

    @State private var shots: [ShotMeta] = []
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            if shots.isEmpty {
                Text("Brak zdjęć. Dotknij +, aby zrobić pierwsze.")
                    .foregroundStyle(.secondary).padding(.top, 80)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(shots) { meta in
                    Button { onOpen(meta.id) } label: { card(meta) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Usuń", role: .destructive) { store.delete(id: meta.id); reload() }
                        }
                }
            }.padding()
        }
        .navigationTitle("R2D2 Pomiar")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onRoomScan) {
                    Label("Skanuj pokój", systemImage: "cube.transparent")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNew) { Image(systemName: "plus.circle.fill") }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { shots = store.list() }

    private func card(_ meta: ShotMeta) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let img = ShotImage.load(meta, store: store)?.preparingThumbnail(of: CGSize(width: 400, height: 400)) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(height: 140).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
            Text(meta.name).font(.subheadline.bold()).lineLimit(1)
            Text("\(meta.measurements.count) pomiarów · \(meta.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
