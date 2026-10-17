import SwiftUI
import RoomPlan
import simd

struct RoomResultView: View {
    let data: CapturedRoomData
    let onDone: () -> Void

    @State private var room: CapturedRoom?
    @State private var elements: [RoomElement] = []
    @State private var processing = true
    @State private var tab = 0
    @State private var selected: RoomElement?
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if processing {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Budowanie modelu 3D…").foregroundStyle(.secondary)
                    }
                } else if room != nil {
                    VStack(spacing: 0) {
                        Picker("", selection: $tab) {
                            Text("Widok 3D").tag(0)
                            Text("Wymiary").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        if tab == 0 {
                            scene3DView
                        } else {
                            listView
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
                    Button { exportUSDZ() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(room == nil)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL { ShareSheet(items: [url]) }
        }
        .alert("Błąd", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
            Button("OK") { errorMsg = nil }
        } message: {
            Text(errorMsg ?? "")
        }
        .task { await buildRoom() }
    }

    // MARK: - 3D

    private var scene3DView: some View {
        ZStack(alignment: .bottom) {
            RoomSceneView(elements: elements, selected: selected) { el in
                withAnimation(.spring(response: 0.3)) { selected = selected?.id == el?.id ? nil : el }
            }
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                legend
                if let s = selected { selectionCard(s) }
            }
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                legendChip("Ściana", .systemGray)
                legendChip("Drzwi", .brown)
                legendChip("Okno", .systemCyan)
                legendChip("Przejście", .systemGreen)
                legendChip("Obiekt", .systemOrange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }

    private func legendChip(_ label: String, _ color: UIColor) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(Color(color)).frame(width: 14, height: 14)
            Text(label).font(.caption2)
        }
    }

    @ViewBuilder
    private func selectionCard(_ el: RoomElement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconName(el.kind))
                    .foregroundStyle(Color(kindColor(el.kind)))
                Text(el.label).font(.headline)
                Spacer()
                Button { withAnimation { selected = nil } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            Text(el.dimLabel)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                dimBadge("szer.", el.dimensions.x)
                dimBadge("wys.", el.dimensions.y)
                dimBadge("głęb.", el.dimensions.z)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
        .padding(.bottom, 28)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func dimBadge(_ label: String, _ meters: Float) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int((Double(meters)*1000).rounded())) mm")
                .font(.caption.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Lista

    private var listView: some View {
        List {
            let grouped = Dictionary(grouping: elements, by: \.kind)
            let order: [RoomElement.Kind] = [.wall, .door, .window, .opening, .object, .floor]
            ForEach(order, id: \.self) { kind in
                if let items = grouped[kind], !items.isEmpty {
                    Section(kindTitle(kind)) {
                        ForEach(items) { el in
                            HStack {
                                Image(systemName: iconName(el.kind))
                                    .foregroundStyle(Color(kindColor(el.kind)))
                                    .frame(width: 24)
                                Text(el.label)
                                Spacer()
                                Text(el.dimLabel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - helpers

    private func kindTitle(_ k: RoomElement.Kind) -> String {
        switch k {
        case .wall: return "Ściany"
        case .door: return "Drzwi"
        case .window: return "Okna"
        case .opening: return "Przejścia"
        case .object: return "Obiekty"
        case .floor: return "Podłogi"
        }
    }

    private func iconName(_ k: RoomElement.Kind) -> String {
        switch k {
        case .wall: return "rectangle.fill"
        case .door: return "door.left.hand.open"
        case .window: return "window.horizontal"
        case .opening: return "arrow.left.and.right"
        case .object: return "cube.fill"
        case .floor: return "square.fill"
        }
    }

    private func kindColor(_ k: RoomElement.Kind) -> UIColor {
        switch k {
        case .wall: return .systemGray
        case .door: return .brown
        case .window: return .systemCyan
        case .opening: return .systemGreen
        case .object: return .systemOrange
        case .floor: return .systemGray2
        }
    }

    private func buildRoom() async {
        do {
            let builder = RoomBuilder(options: [.beautifyObjects])
            let captured = try await builder.capturedRoom(from: data)
            let els = RoomElement.from(captured)
            await MainActor.run {
                room = captured
                elements = els
                processing = false
            }
        } catch {
            await MainActor.run { errorMsg = error.localizedDescription; processing = false }
        }
    }

    private func exportUSDZ() {
        guard let room else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokoj-\(Int(Date().timeIntervalSince1970)).usdz")
        do {
            try room.export(to: url)
            exportURL = url
            showShare = true
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
