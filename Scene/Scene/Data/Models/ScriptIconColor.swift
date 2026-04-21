import SwiftUI

enum ScriptIconColor: String, CaseIterable, Identifiable {
    case red    = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green  = "green"
    case blue   = "blue"
    case purple = "purple"
    case gray   = "gray"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red:    return Color(red: 0.90, green: 0.22, blue: 0.21)
        case .orange: return Color(red: 0.96, green: 0.50, blue: 0.10)
        case .yellow: return Color(red: 0.96, green: 0.76, blue: 0.19)
        case .green:  return Color(red: 0.18, green: 0.65, blue: 0.32)
        case .blue:   return Color(red: 0.22, green: 0.56, blue: 0.94)
        case .purple: return Color(red: 0.60, green: 0.25, blue: 0.75)
        case .gray:   return Color(red: 0.55, green: 0.55, blue: 0.57)
        }
    }
}
