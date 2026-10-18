import SwiftUI

struct MeasureView: View {
    @ObservedObject var viewModel: MeasureViewModel
    let image: UIImage            // obrócony do orientacji wyświetlania
    let onShare: () -> Void

    private enum Drag { case move(DragTarget), place }
    @State private var drag: Drag?
    @State private var touch: CGPoint?
    @State private var name: String
    @State private var isManualMode = false
    @State private var pendingManualSheet: ManualPoint? = nil
    @State private var manualInput = ""

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
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                    Canvas { ctx, _ in draw(ctx, layout) }
                        .allowsHitTesting(false)
                    if let t = touch, layout.rect.width > 0 {
                        let loupeOffset: CGFloat = 130
                        let loupeX = min(max(t.x, 70), geo.size.width - 70)
                        let loupeY = t.y > loupeOffset
                            ? t.y - loupeOffset
                            : min(t.y + loupeOffset, geo.size.height - 70)
                        LoupeView(image: image, imageSize: layout.rect.size, center: layout.displayPoint(t))
                            .position(x: loupeX, y: loupeY)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in onChanged(g.location, layout) }
                        .onEnded { g in onEnded(g.location, layout) }
                )
            }
            list
        }
        .navigationTitle(viewModel.meta.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isManualMode.toggle()
                } label: {
                    Label(isManualMode ? "Ręczny" : "Auto",
                          systemImage: isManualMode ? "pencil.circle.fill" : "sensor.tag.radiowaves.forward")
                        .font(.caption)
                }
                .tint(isManualMode ? .orange : .blue)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { onShare() } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(viewModel.meta.measurements.isEmpty)
            }
        }
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
                        Button("Anuluj") {
                            viewModel.cancelPending()
                            pendingManualSheet = nil
                        }
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
    }

    // MARK: gesty

    private func project(_ layout: ImageLayout) -> (NormalizedPoint) -> CGPoint {
        { sensor in layout.viewPoint(SensorGeometry.toDisplay(sensor, orientation)) }
    }

    private func sensorPoint(_ v: CGPoint, _ layout: ImageLayout) -> NormalizedPoint {
        SensorGeometry.toSensor(layout.displayPoint(v), orientation)
    }

    private func onChanged(_ loc: CGPoint, _ layout: ImageLayout) {
        touch = loc
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

    // MARK: rysowanie

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
            let labelText = r.label + (isManual ? " ✎" : "")
            let text = ctx.resolve(Text(labelText).font(.system(size: 14, weight: .bold)).foregroundColor(.black))
            let size = text.measure(in: CGSize(width: 200, height: 40))
            let box = CGRect(x: mid.x - size.width / 2 - 6, y: mid.y - size.height / 2 - 3,
                             width: size.width + 12, height: size.height + 6)
            ctx.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(.white.opacity(0.9)))
            ctx.draw(text, at: mid)
        }
        if let a = viewModel.pendingA {
            let pt = proj(a)
            ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)),
                       with: .color(.yellow), lineWidth: 3)
        }
    }

    // MARK: lista

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
                            ? "Tryb ręczny: zaznacz punkt A, potem B — wpiszesz odległość."
                            : "Przyłóż palec, przeciągnij lupą na punkt i puść — to punkt A. Potem tak samo punkt B.")
                         : "Teraz wskaż punkt B.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(viewModel.meta.measurements) { m in
                    let r = viewModel.result(for: m)
                    HStack {
                        Circle().fill(m.manualMM != nil ? Color.orange : r.reliability.color).frame(width: 10, height: 10)
                        Text(r.label + (m.manualMM != nil ? " ✎" : "")).font(.headline.monospacedDigit())
                        if r.perspectiveWarning {
                            Image(systemName: "perspective")
                                .foregroundStyle(.orange)
                                .help("Pomiar ukośny — sfotografuj obiekt bardziej na wprost lub użyj zoomu")
                        }
                        Spacer()
                        Button(role: .destructive) { viewModel.delete(m.id) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .frame(maxHeight: 260)
    }
}
