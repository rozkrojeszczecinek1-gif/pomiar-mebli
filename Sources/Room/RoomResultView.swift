import SwiftUI
import RoomPlan
import simd

struct RoomResultView: View {
    let data: CapturedRoomData
    let onDone: () -> Void

    @State private var room: CapturedRoom?
    @State private var processing = true
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Group {
                if processing {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Budowanie modelu 3D…").foregroundStyle(.secondary)
                    }
                } else if let room {
                    List {
                        if !room.walls.isEmpty {
                            Section("Ściany (\(room.walls.count))") {
                                ForEach(Array(room.walls.enumerated()), id: \.offset) { i, w in
                                    dimensionRow(label: "Ściana \(i + 1)", dims: w.dimensions)
                                }
                            }
                        }
                        if !room.doors.isEmpty {
                            Section("Drzwi (\(room.doors.count))") {
                                ForEach(Array(room.doors.enumerated()), id: \.offset) { i, d in
                                    dimensionRow(label: "Drzwi \(i + 1)", dims: d.dimensions)
                                }
                            }
                        }
                        if !room.windows.isEmpty {
                            Section("Okna (\(room.windows.count))") {
                                ForEach(Array(room.windows.enumerated()), id: \.offset) { i, w in
                                    dimensionRow(label: "Okno \(i + 1)", dims: w.dimensions)
                                }
                            }
                        }
                        if !room.objects.isEmpty {
                            Section("Obiekty (\(room.objects.count))") {
                                ForEach(Array(room.objects.enumerated()), id: \.offset) { i, o in
                                    dimensionRow(label: o.category.label, dims: o.dimensions)
                                }
                            }
                        }
                        if !room.openings.isEmpty {
                            Section("Przejścia (\(room.openings.count))") {
                                ForEach(Array(room.openings.enumerated()), id: \.offset) { i, op in
                                    dimensionRow(label: "Przejście \(i + 1)", dims: op.dimensions)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Brak danych skanu", systemImage: "cube.transparent")
                }
            }
            .navigationTitle("Wynik skanowania")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Gotowe", action: onDone)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportUSDZ()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(room == nil)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Błąd eksportu", isPresented: Binding(
            get: { errorMsg != nil },
            set: { if !$0 { errorMsg = nil } }
        )) {
            Button("OK") { errorMsg = nil }
        } message: {
            Text(errorMsg ?? "")
        }
        .task { await buildRoom() }
    }

    @ViewBuilder
    private func dimensionRow(label: String, dims: simd_float3) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(mm(dims.x)) × \(mm(dims.y)) × \(mm(dims.z)) mm")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func mm(_ v: Float) -> String { "\(Int((Double(v) * 1000).rounded()))" }

    private func buildRoom() async {
        do {
            let builder = RoomBuilder(options: [.beautifyObjects])
            let captured = try await builder.capturedRoom(from: data)
            await MainActor.run {
                room = captured
                processing = false
            }
        } catch {
            await MainActor.run {
                errorMsg = error.localizedDescription
                processing = false
            }
        }
    }

    private func exportUSDZ() {
        guard let room else { return }
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("pokój-\(Date().timeIntervalSince1970).usdz")
        do {
            try room.export(to: url)
            exportURL = url
            showShare = true
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

private extension CapturedRoom.Object.Category {
    var label: String {
        switch self {
        case .storage:      return "Szafa/regał"
        case .refrigerator: return "Lodówka"
        case .stove:        return "Kuchenka"
        case .bed:          return "Łóżko"
        case .sink:         return "Zlew/umywalka"
        case .bathtub:      return "Wanna"
        case .oven:         return "Piekarnik"
        case .dishwasher:   return "Zmywarka"
        case .television:   return "TV"
        case .sofa:         return "Sofa"
        case .chair:        return "Krzesło"
        case .table:        return "Stół"
        case .stairs:       return "Schody"
        case .fireplace:    return "Kominek"
        @unknown default:   return "Obiekt"
        }
    }
}
