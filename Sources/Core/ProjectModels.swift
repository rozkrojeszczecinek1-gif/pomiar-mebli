import Foundation

struct ProjectMeta: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
}

final class ProjectStore: ObservableObject {
    let root: URL
    private let fm = FileManager.default
    @Published private(set) var projects: [ProjectMeta] = []

    init() {
        root = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        migrateIfNeeded()
        reload()
    }

    func reload() {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        projects = dirs.compactMap { d -> ProjectMeta? in
            guard let data = try? Data(contentsOf: d.appendingPathComponent("project.json")) else { return nil }
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try? dec.decode(ProjectMeta.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func create(name: String) throws -> ProjectMeta {
        let meta = ProjectMeta(id: UUID(), name: name, createdAt: Date())
        let dir = projectDir(meta.id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Shots"), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .prettyPrinted
        try enc.encode(meta).write(to: dir.appendingPathComponent("project.json"), options: .atomic)
        reload()
        return meta
    }

    func rename(_ id: UUID, to name: String) {
        guard var meta = projects.first(where: { $0.id == id }) else { return }
        meta.name = name
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .prettyPrinted
        try? enc.encode(meta).write(to: projectDir(id).appendingPathComponent("project.json"), options: .atomic)
        reload()
    }

    func delete(_ id: UUID) {
        try? fm.removeItem(at: projectDir(id))
        reload()
    }

    func shotStore(for project: ProjectMeta) -> ShotStore {
        ShotStore(root: projectDir(project.id).appendingPathComponent("Shots"))
    }

    func shotCount(for project: ProjectMeta) -> Int {
        let shotsDir = projectDir(project.id).appendingPathComponent("Shots")
        return (try? fm.contentsOfDirectory(at: shotsDir, includingPropertiesForKeys: nil))?.count ?? 0
    }

    private func projectDir(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func migrateIfNeeded() {
        let oldShotsDir = root.deletingLastPathComponent().appendingPathComponent("Shots")
        guard fm.fileExists(atPath: oldShotsDir.path) else { return }
        let dirs = (try? fm.contentsOfDirectory(at: oldShotsDir, includingPropertiesForKeys: nil)) ?? []
        guard !dirs.isEmpty else { return }
        let migrated: ProjectMeta
        do { migrated = try create(name: "Moje pomiary") } catch { return }
        let dest = projectDir(migrated.id).appendingPathComponent("Shots")
        for shotDir in dirs {
            let target = dest.appendingPathComponent(shotDir.lastPathComponent)
            try? fm.moveItem(at: shotDir, to: target)
        }
        try? fm.removeItem(at: oldShotsDir)
    }
}
