import Foundation

final class ShotStore {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) {
        self.root = root
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static func defaultRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shots", isDirectory: true)
    }

    private func dir(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func imageURL(for id: UUID) -> URL { dir(id).appendingPathComponent("foto.jpg") }
    private func depthURL(_ id: UUID) -> URL { dir(id).appendingPathComponent("depth.bin") }
    private func metaURL(_ id: UUID) -> URL { dir(id).appendingPathComponent("meta.json") }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func save(_ shot: CapturedShot, name: String, now: Date = Date()) throws -> ShotMeta {
        let meta = ShotMeta(id: UUID(), name: name, createdAt: now, intrinsics: shot.intrinsics,
                            depthWidth: shot.depth.width, depthHeight: shot.depth.height,
                            orientation: shot.orientation, measurements: [])
        try fm.createDirectory(at: dir(meta.id), withIntermediateDirectories: true)
        try shot.jpeg.write(to: imageURL(for: meta.id), options: .atomic)
        try shot.depth.encoded().write(to: depthURL(meta.id), options: .atomic)
        try encoder.encode(meta).write(to: metaURL(meta.id), options: .atomic)
        return meta
    }

    func update(_ meta: ShotMeta) throws {
        try encoder.encode(meta).write(to: metaURL(meta.id), options: .atomic)
    }

    func list() -> [ShotMeta] {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { d -> ShotMeta? in
            guard let data = try? Data(contentsOf: d.appendingPathComponent("meta.json")) else { return nil }
            return try? decoder.decode(ShotMeta.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func loadDepth(_ meta: ShotMeta) -> DepthMap? {
        guard let data = try? Data(contentsOf: depthURL(meta.id)) else { return nil }
        return DepthMap(data: data, width: meta.depthWidth, height: meta.depthHeight)
    }

    func delete(id: UUID) {
        try? fm.removeItem(at: dir(id))
    }
}
