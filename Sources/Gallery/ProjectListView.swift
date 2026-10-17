import SwiftUI

struct ProjectListView: View {
    @ObservedObject var store: ProjectStore
    let onSelect: (ProjectMeta) -> Void

    @State private var showNew = false
    @State private var newName = ""
    @State private var renaming: ProjectMeta?
    @State private var renameName = ""

    var body: some View {
        List {
            if store.projects.isEmpty {
                Text("Brak projektów. Utwórz pierwszy projekt przyciskiem +.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            ForEach(store.projects) { project in
                Button {
                    onSelect(project)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).font(.headline).foregroundStyle(.primary)
                            Text("\(store.shotCount(for: project)) zdjęć · \(project.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                    }
                }
                .contextMenu {
                    Button {
                        renameName = project.name
                        renaming = project
                    } label: {
                        Label("Zmień nazwę", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        store.delete(project.id)
                    } label: {
                        Label("Usuń projekt", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("R2D2 Pomiar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newName = ""; showNew = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .alert("Nowy projekt", isPresented: $showNew) {
            TextField("Nazwa projektu", text: $newName)
            Button("Utwórz") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { try? store.create(name: name) }
            }
            Button("Anuluj", role: .cancel) {}
        }
        .alert("Zmień nazwę", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nazwa projektu", text: $renameName)
            Button("Zapisz") {
                if let p = renaming {
                    let name = renameName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { store.rename(p.id, to: name) }
                }
                renaming = nil
            }
            Button("Anuluj", role: .cancel) { renaming = nil }
        }
        .onAppear { store.reload() }
    }
}
