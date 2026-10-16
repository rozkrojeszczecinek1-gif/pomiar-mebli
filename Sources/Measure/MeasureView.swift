import SwiftUI

struct MeasureView: View {
    @ObservedObject var viewModel: MeasureViewModel
    let image: UIImage            // obrócony do orientacji wyświetlania
    let onShare: () -> Void

    private enum Drag { case move(DragTarget), place }
    @State private var drag: Drag?
    @State private var touch: CGPoint?
    @State private var name = ""

    private var orientation: ImageOrientation { viewModel.meta.orientation }
    private let hitRadius: CGFloat = 28

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
                        LoupeView(image: image, imageSize: layout.rect.size, center: layout.displayPoint(t))
                            .position(x: min(max(t.x, 70), geo.size.width - 70), y: max(t.y - 100, 70))
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
            ToolbarItem(placement: .topBarTrailing) {
                Button { onShare() } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(viewModel.meta.measurements.isEmpty)
            }
        }
        .onAppear { name = viewModel.meta.name }
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
        case .move: viewModel.commit()
        case .place: viewModel.place(at: sensorPoint(loc, layout))
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
            var line = Path(); line.move(to: a); line.addLine(to: b)
            ctx.stroke(line, with: .color(r.reliability.color), lineWidth: 2.5)
            for pt in [a, b] {
                let dot = Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12))
                ctx.fill(dot, with: .color(r.reliability.color))
                ctx.stroke(dot, with: .color(.white), lineWidth: 1.5)
            }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let text = ctx.resolve(Text(r.label).font(.system(size: 14, weight: .bold)).foregroundColor(.black))
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
                         ? "Przyłóż palec, przeciągnij lupą na punkt i puść — to punkt A. Potem tak samo punkt B."
                         : "Teraz wskaż punkt B.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(viewModel.meta.measurements) { m in
                    let r = viewModel.result(for: m)
                    HStack {
                        Circle().fill(r.reliability.color).frame(width: 10, height: 10)
                        Text(r.label).font(.headline.monospacedDigit())
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
