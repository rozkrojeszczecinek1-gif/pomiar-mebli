import SwiftUI
import Vision

struct MeasureView: View {
    @ObservedObject var viewModel: MeasureViewModel
    let image: UIImage
    let onShare: () -> Void

    private enum Drag { case move(DragTarget), place }
    @State private var drag: Drag?
    @State private var touch: CGPoint?
    @State private var name: String
    @State private var isManualMode = false
    @State private var isDetecting = false
    @State private var detectError: String? = nil
    @State private var pendingManualSheet: ManualPoint? = nil
    @State private var manualInput = ""
    @State private var editingMeasurement: Measurement? = nil
    @State private var editManualInput = ""
    @State private var editNameInput = ""

    // Zoom state
    @State private var photoZoom: CGFloat = 1.0
    @GestureState private var pinchScale: CGFloat = 1.0

    private var orientation: ImageOrientation { viewModel.meta.orientation }
    private let hitRadius: CGFloat = 28

    private struct ManualPoint: Identifiable {
        let id = UUID()
        let point: NormalizedPoint
    }

    init(viewModel: MeasureViewModel, image: UIImage, onShare: @escaping () -> Void) {
        self.viewModel = viewModel
        self.image = image
        self.onShare = onShare
        self._name = State(initialValue: viewModel.meta.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let layout = ImageLayout(container: geo.size, displayed: image.size)
                ZStack {
                    // Zoomable content
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                        Canvas { ctx, _ in draw(ctx, layout) }
                            .allowsHitTesting(false)
                    }
                    .scaleEffect(photoZoom * pinchScale)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .updating($pinchScale) { v, s, _ in s = v }
                                .onEnded { v in
                                    photoZoom = min(max(photoZoom * v, 1.0), 8.0)
                                },
                            DragGesture(minimumDistance: 0)
                                .onChanged { g in
                                    guard abs(pinchScale - 1.0) < 0.05 else { return }
                                    touch = g.location
                                    onChanged(content(g.location, geo.size), layout)
                                }
                                .onEnded { g in
                                    guard abs(pinchScale - 1.0) < 0.05 else {
                                        touch = nil; drag = nil; return
                                    }
                                    onEnded(content(g.location, geo.size), layout)
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) { photoZoom = 1.0 }
                    }

                    // Loupe — outside scaled ZStack so it stays same size
                    if let t = touch, layout.rect.width > 0, photoZoom * pinchScale < 2.5 {
                        let tc = content(t, geo.size)
                        let loupeOffset: CGFloat = 130
                        let loupeX = min(max(t.x, 70), geo.size.width - 70)
                        let loupeY = t.y > loupeOffset
                            ? t.y - loupeOffset
                            : min(t.y + loupeOffset, geo.size.height - 70)
                        LoupeView(image: image, imageSize: layout.rect.size, center: layout.displayPoint(tc))
                            .position(x: loupeX, y: loupeY)
                            .allowsHitTesting(false)
                    }

                    // Zoom hint
                    if photoZoom > 1.05 {
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    withAnimation(.spring(response: 0.3)) { photoZoom = 1.0 }
                                } label: {
                                    Label(String(format: "%.1f×", photoZoom * pinchScale), systemImage: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption)
                                        .padding(6).background(.ultraThinMaterial, in: Capsule())
                                }
                                .padding(8)
                            }
                            Spacer()
                        }
                    }
                }
            }
            list
        }
        .navigationTitle(viewModel.meta.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { isManualMode.toggle() } label: {
                    Label(isManualMode ? "Ręczny" : "Auto",
                          systemImage: isManualMode ? "pencil.circle.fill" : "sensor.tag.radiowaves.forward")
                        .font(.caption)
                }
                .tint(isManualMode ? .orange : .blue)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await detectEdges() }
                } label: {
                    if isDetecting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkle.magnifyingglass")
                    }
                }
                .disabled(isDetecting)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { onShare() } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(viewModel.meta.measurements.isEmpty)
            }
        }
        .alert("Brak detekcji", isPresented: Binding(get: { detectError != nil },
                                                    set: { if !$0 { detectError = nil } })) {
            Button("OK") { detectError = nil }
        } message: { Text(detectError ?? "") }
        .alert("Nie można zapisać pomiarów", isPresented: $viewModel.saveError) {
            Button("OK") { viewModel.saveError = false }
        } message: {
            Text("Sprawdź dostępne miejsce na dysku.")
        }
        .sheet(item: $pendingManualSheet) { item in
            NavigationStack {
                VStack(spacing: 20) {
                    Text("Wpisz rzeczywistą odległość")
                        .font(.headline)
                    TextField("np. 850", text: $manualInput)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .padding(.horizontal)
                    Text("milimetry (mm)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("Pomiar ręczny")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Anuluj") { viewModel.cancelPending(); pendingManualSheet = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Zapisz") {
                            if let mm = Double(manualInput.replacingOccurrences(of: ",", with: ".")), mm > 0 {
                                viewModel.placeManual(b: item.point, mm: mm)
                            }
                            pendingManualSheet = nil
                        }
                        .disabled(Double(manualInput.replacingOccurrences(of: ",", with: ".")) == nil)
                    }
                }
            }
            .presentationDetents([.height(260)])
        }
        .sheet(item: $editingMeasurement) { m in
            NavigationStack {
                Form {
                    Section("Nazwa (opcjonalnie)") {
                        TextField("np. Szerokość szafy", text: $editNameInput)
                    }
                    Section("Wartość (mm)") {
                        TextField("np. 850", text: $editManualInput)
                            .keyboardType(.decimalPad)
                        if m.manualMM != nil {
                            Button("Usuń wartość ręczną — wróć do LiDAR") {
                                viewModel.setManual(nil, for: m.id)
                                editingMeasurement = nil
                            }
                            .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle("Edycja pomiaru")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Anuluj") { editingMeasurement = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Zapisz") {
                            viewModel.setName(editNameInput, for: m.id)
                            let raw = editManualInput.replacingOccurrences(of: ",", with: ".")
                            if let mm = Double(raw), mm > 0 { viewModel.setManual(mm, for: m.id) }
                            editingMeasurement = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - AI edge detection

    @MainActor
    private func detectEdges() async {
        guard let cg = image.cgImage else { return }
        isDetecting = true
        defer { isDetecting = false }

        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.4
        request.minimumSize = 0.08
        request.maximumObservations = 10

        // Vision zwraca punkty w układzie obrazu po uwzględnieniu orientacji UIImage,
        // czyli w tym samym układzie co wyświetlane zdjęcie (origin lewy-dolny).
        let handler = VNImageRequestHandler(cgImage: cg,
                                            orientation: CGImagePropertyOrientation(image.imageOrientation),
                                            options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results,
              !results.isEmpty else {
            detectError = "Nie wykryto prostokątów w tym zdjęciu."
            return
        }

        let orient = orientation
        func toSensor(_ pt: CGPoint) -> NormalizedPoint {
            SensorGeometry.toSensor(NormalizedPoint(x: Double(pt.x), y: Double(1 - pt.y)), orient)
        }
        var batch: [Measurement] = []
        for obs in results {
            let tl = toSensor(obs.topLeft), tr = toSensor(obs.topRight), br = toSensor(obs.bottomRight)
            batch.append(Measurement(a: tl, b: tr, name: "Szerokość"))
            batch.append(Measurement(a: tr, b: br, name: "Wysokość"))
        }
        viewModel.addBatch(batch)
    }

    // MARK: - Zoom helper

    private func content(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        let z = photoZoom * pinchScale
        guard z > 0.01 else { return p }
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(x: (p.x - cx) / z + cx, y: (p.y - cy) / z + cy)
    }

    // MARK: - Gestures

    private func project(_ layout: ImageLayout) -> (NormalizedPoint) -> CGPoint {
        { sensor in layout.viewPoint(SensorGeometry.toDisplay(sensor, orientation)) }
    }

    private func sensorPoint(_ v: CGPoint, _ layout: ImageLayout) -> NormalizedPoint {
        SensorGeometry.toSensor(layout.displayPoint(v), orientation)
    }

    private func onChanged(_ loc: CGPoint, _ layout: ImageLayout) {
        if drag == nil {
            if let t = viewModel.hit(at: loc, radius: hitRadius, project: project(layout)) {
                drag = .move(t)
            } else {
                drag = .place
            }
        }
        if case .move(let t) = drag { viewModel.move(t, to: sensorPoint(loc, layout)) }
    }

    private func onEnded(_ loc: CGPoint, _ layout: ImageLayout) {
        switch drag {
        case .move:
            viewModel.commit()
        case .place:
            let sp = sensorPoint(loc, layout)
            if isManualMode && viewModel.pendingA != nil {
                manualInput = ""
                pendingManualSheet = ManualPoint(point: sp)
            } else {
                viewModel.place(at: sp)
            }
        case nil: break
        }
        drag = nil
        touch = nil
    }

    // MARK: - Canvas

    private func draw(_ ctx: GraphicsContext, _ layout: ImageLayout) {
        let proj = project(layout)
        for m in viewModel.meta.measurements {
            let a = proj(m.a), b = proj(m.b)
            let r = viewModel.result(for: m)
            let isManual = m.manualMM != nil
            let lineColor: Color = isManual ? .orange : r.reliability.color
            var line = Path(); line.move(to: a); line.addLine(to: b)
            ctx.stroke(line, with: .color(lineColor), lineWidth: 2.5)
            for pt in [a, b] {
                let dot = Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12))
                ctx.fill(dot, with: .color(lineColor))
                ctx.stroke(dot, with: .color(.white), lineWidth: 1.5)
            }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let valueStr = r.label + (isManual ? " ✎" : "")
            let labelText = m.name.map { "\($0): \(valueStr)" } ?? valueStr
            let text = ctx.resolve(Text(labelText).font(.system(size: 13, weight: .bold)).foregroundColor(.black))
            let size = text.measure(in: CGSize(width: 260, height: 40))
            let box = CGRect(x: mid.x - size.width / 2 - 6, y: mid.y - size.height / 2 - 3,
                             width: size.width + 12, height: size.height + 6)
            ctx.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(.white.opacity(0.92)))
            ctx.draw(text, at: mid)
        }
        if let a = viewModel.pendingA {
            let pt = proj(a)
            ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)),
                       with: .color(.yellow), lineWidth: 3)
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            Section {
                TextField("Nazwa zdjęcia", text: $name)
                    .onSubmit { viewModel.rename(name) }
            }
            Section("Pomiary") {
                if viewModel.meta.measurements.isEmpty {
                    Text(viewModel.pendingA == nil
                         ? (isManualMode
                            ? "Tryb ręczny: zaznacz A, potem B — wpiszesz odległość."
                            : "Przytknij palec, lupą celuj w punkt i puść — punkt A. Potem B.")
                         : "Teraz wskaż punkt B.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(viewModel.meta.measurements) { m in
                    let r = viewModel.result(for: m)
                    HStack {
                        Circle().fill(m.manualMM != nil ? Color.orange : r.reliability.color)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.label + (m.manualMM != nil ? " ✎" : ""))
                                .font(.headline.monospacedDigit())
                            if let n = m.name {
                                Text(n).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if r.perspectiveWarning {
                            Image(systemName: "perspective").foregroundStyle(.orange)
                        }
                        Spacer()
                        Button {
                            editManualInput = m.manualMM.map { String(format: "%.0f", $0) } ?? ""
                            editNameInput = m.name ?? ""
                            editingMeasurement = m
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless).tint(.orange)
                        Button(role: .destructive) { viewModel.delete(m.id) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
