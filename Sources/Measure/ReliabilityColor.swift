import SwiftUI

extension Reliability {
    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        }
    }
}
