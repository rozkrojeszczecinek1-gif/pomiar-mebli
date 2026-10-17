import Foundation
import RoomPlan
import simd

struct RoomElement: Identifiable, Equatable {
    enum Kind: String { case wall, door, window, opening, object, floor }

    let id: String
    let kind: Kind
    let dimensions: simd_float3
    let label: String
    let transform: simd_float4x4

    static func == (l: RoomElement, r: RoomElement) -> Bool { l.id == r.id }

    var dimLabel: String {
        let w = Int((Double(dimensions.x) * 1000).rounded())
        let h = Int((Double(dimensions.y) * 1000).rounded())
        let d = Int((Double(dimensions.z) * 1000).rounded())
        return "\(w) × \(h) × \(d) mm"
    }

    static func from(_ room: CapturedRoom) -> [RoomElement] {
        var result: [RoomElement] = []
        for (i, s) in room.walls.enumerated() {
            result.append(RoomElement(id: "wall_\(i)", kind: .wall, dimensions: s.dimensions,
                                      label: "Ściana \(i+1)", transform: s.transform))
        }
        for (i, s) in room.doors.enumerated() {
            result.append(RoomElement(id: "door_\(i)", kind: .door, dimensions: s.dimensions,
                                      label: "Drzwi \(i+1)", transform: s.transform))
        }
        for (i, s) in room.windows.enumerated() {
            result.append(RoomElement(id: "window_\(i)", kind: .window, dimensions: s.dimensions,
                                      label: "Okno \(i+1)", transform: s.transform))
        }
        for (i, s) in room.openings.enumerated() {
            result.append(RoomElement(id: "opening_\(i)", kind: .opening, dimensions: s.dimensions,
                                      label: "Przejście \(i+1)", transform: s.transform))
        }
        for (i, o) in room.objects.enumerated() {
            result.append(RoomElement(id: "object_\(i)", kind: .object, dimensions: o.dimensions,
                                      label: o.category.label, transform: o.transform))
        }
        if #available(iOS 16, *) {
            for (i, s) in room.floors.enumerated() {
                result.append(RoomElement(id: "floor_\(i)", kind: .floor, dimensions: s.dimensions,
                                          label: "Podłoga \(i+1)", transform: s.transform))
            }
        }
        return result
    }
}

extension CapturedRoom.Object.Category {
    var label: String {
        switch self {
        case .storage:      return "Szafa/regał"
        case .refrigerator: return "Lodówka"
        case .stove:        return "Kuchenka"
        case .bed:          return "Łóżko"
        case .sink:         return "Zlew/umywalka"
        case .bathtub:      return "Wanna"
        case .toilet:       return "Toaleta"
        case .washerDryer:  return "Pralka/suszarka"
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
