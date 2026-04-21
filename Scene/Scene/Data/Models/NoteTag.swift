import SwiftUI

enum NoteTag: String, CaseIterable, Codable, Identifiable {
    case character  = "Character"
    case plot       = "Plot"
    case structure  = "Structure"
    case dialogue   = "Dialogue"
    case theme      = "Theme"
    case setupPayoff = "Setup/Payoff"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .character:   return .blue
        case .plot:        return .orange
        case .structure:   return .purple
        case .dialogue:    return .green
        case .theme:       return .red
        case .setupPayoff: return .teal
        }
    }

    var icon: String {
        switch self {
        case .character:   return "person.fill"
        case .plot:        return "arrow.triangle.branch"
        case .structure:   return "rectangle.3.group"
        case .dialogue:    return "bubble.left.fill"
        case .theme:       return "sparkles"
        case .setupPayoff: return "arrow.uturn.right"
        }
    }
}
