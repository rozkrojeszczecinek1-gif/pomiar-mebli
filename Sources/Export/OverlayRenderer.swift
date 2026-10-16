import UIKit

struct OverlayLine: Equatable {
    var a: CGPoint
    var b: CGPoint
    var label: String
    var reliability: Reliability
}

enum OverlayRenderer {
    static func lines(for meta: ShotMeta, depth: DepthMap, displayedSize: CGSize) -> [OverlayLine] {
        meta.measurements.map { m in
            let r = MeasureEngine.measure(depth, meta.intrinsics, from: m.a, to: m.b)
            func px(_ s: NormalizedPoint) -> CGPoint {
                let d = SensorGeometry.toDisplay(s, meta.orientation)
                return CGPoint(x: d.x * displayedSize.width, y: d.y * displayedSize.height)
            }
            return OverlayLine(a: px(m.a), b: px(m.b), label: r.label, reliability: r.reliability)
        }
    }

    static func render(image: UIImage, lines: [OverlayLine], title: String?) -> Data? {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let unit = max(size.width, size.height) / 350      // grubość linii
        let font = UIFont.boldSystemFont(ofSize: max(size.width, size.height) / 40)

        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            let g = ctx.cgContext
            for l in lines {
                let color = uiColor(l.reliability)
                g.setStrokeColor(color.cgColor); g.setLineWidth(unit)
                g.move(to: l.a); g.addLine(to: l.b); g.strokePath()
                for p in [l.a, l.b] {
                    let r = unit * 2
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
                    g.setFillColor(color.cgColor); g.fillEllipse(in: rect)
                    g.setStrokeColor(UIColor.white.cgColor); g.setLineWidth(unit / 2); g.strokeEllipse(in: rect)
                }
                drawPill(l.label, at: CGPoint(x: (l.a.x + l.b.x) / 2, y: (l.a.y + l.b.y) / 2), font: font, in: g)
            }
            if let title, !title.isEmpty {
                drawPill(title, at: CGPoint(x: size.width / 2, y: font.lineHeight * 1.2), font: font, in: g)
            }
        }
        return img.jpegData(compressionQuality: 0.9)
    }

    private static func uiColor(_ r: Reliability) -> UIColor {
        switch r {
        case .green: return UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1)
        case .yellow: return UIColor.orange
        case .red: return UIColor.red
        }
    }

    private static func drawPill(_ text: String, at center: CGPoint, font: UIFont, in g: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let s = (text as NSString).size(withAttributes: attrs)
        let pad = font.pointSize * 0.4
        let box = CGRect(x: center.x - s.width / 2 - pad, y: center.y - s.height / 2 - pad / 2,
                         width: s.width + 2 * pad, height: s.height + pad)
        g.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        g.addPath(UIBezierPath(roundedRect: box, cornerRadius: pad).cgPath); g.fillPath()
        (text as NSString).draw(at: CGPoint(x: center.x - s.width / 2, y: center.y - s.height / 2), withAttributes: attrs)
    }
}
