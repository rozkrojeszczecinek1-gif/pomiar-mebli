import UIKit

/// Jak obrócić obraz sensora (landscape), żeby wyświetlić go w prawidłowej orientacji.
enum ImageOrientation: Int, Codable {
    case up = 0, down, left, right

    var uiOrientation: UIImage.Orientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

enum SensorGeometry {
    static func displayedSize(sensorWidth w: Double, sensorHeight h: Double,
                              orientation o: ImageOrientation) -> (width: Double, height: Double) {
        switch o {
        case .up, .down: return (w, h)
        case .left, .right: return (h, w)
        }
    }

    static func toDisplay(_ p: NormalizedPoint, _ o: ImageOrientation) -> NormalizedPoint {
        switch o {
        case .up: return p
        case .down: return NormalizedPoint(x: 1 - p.x, y: 1 - p.y)
        case .right: return NormalizedPoint(x: 1 - p.y, y: p.x)
        case .left: return NormalizedPoint(x: p.y, y: 1 - p.x)
        }
    }

    static func toSensor(_ d: NormalizedPoint, _ o: ImageOrientation) -> NormalizedPoint {
        switch o {
        case .up: return d
        case .down: return NormalizedPoint(x: 1 - d.x, y: 1 - d.y)
        case .right: return NormalizedPoint(x: d.y, y: 1 - d.x)
        case .left: return NormalizedPoint(x: 1 - d.y, y: d.x)
        }
    }

    /// ARKit zwraca obraz w orientacji landscape (sensor). Portret = obrót o 90° w prawo.
    static func imageOrientation(for device: UIDeviceOrientation) -> ImageOrientation {
        switch device {
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        default: return .right
        }
    }
}

/// Położenie obrazu (aspect-fit) w widoku i konwersja punktów.
struct ImageLayout: Equatable {
    let rect: CGRect

    init(container: CGSize, displayed: CGSize) {
        guard container.width > 0, container.height > 0, displayed.width > 0, displayed.height > 0 else {
            rect = .zero
            return
        }
        let s = min(container.width / displayed.width, container.height / displayed.height)
        let w = displayed.width * s
        let h = displayed.height * s
        rect = CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    func viewPoint(_ d: NormalizedPoint) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(d.x) * rect.width, y: rect.minY + CGFloat(d.y) * rect.height)
    }

    func displayPoint(_ v: CGPoint) -> NormalizedPoint {
        guard rect.width > 0, rect.height > 0 else { return NormalizedPoint(x: 0, y: 0) }
        let x = min(max(Double((v.x - rect.minX) / rect.width), 0), 1)
        let y = min(max(Double((v.y - rect.minY) / rect.height), 0), 1)
        return NormalizedPoint(x: x, y: y)
    }
}
