import SwiftUI
import UIKit

struct PDFDialogueHighlightSettings: Equatable {
    var isEnabled = false
    var mutedCharacters: Set<String> = []
    var isMuteAll = false
    var activeTurnSequenceIndex: Int?
    var isActiveTurnOnly = false

    func shouldShow(turn: ScriptDialogueTurn) -> Bool {
        if isActiveTurnOnly {
            return isEnabled && turn.sequenceIndex == activeTurnSequenceIndex
        }

        if let activeTurnSequenceIndex {
            return isEnabled && turn.sequenceIndex == activeTurnSequenceIndex
        }

        return shouldShow(characterName: turn.characterName)
    }

    private func shouldShow(characterName: String) -> Bool {
        isEnabled && !isMuteAll && !mutedCharacters.contains(characterName)
    }
}

enum PDFDialogueHighlightPalette {
    private static let baseColors: [UIColor] = [
        .systemOrange,
        .systemBlue,
        .systemPurple,
        .systemGreen,
        .systemPink,
        .systemTeal,
        .systemRed,
        .systemIndigo,
        .systemBrown,
        .systemCyan
    ]

    static func uiColor(
        for characterName: String,
        allCharacters: [String],
        alpha: CGFloat = 1
    ) -> UIColor {
        let names = Array(Set(allCharacters)).sorted()
        let index = names.firstIndex(of: characterName) ?? 0
        return baseColors[index % baseColors.count].withAlphaComponent(alpha)
    }

    static func swiftUIColor(for characterName: String, allCharacters: [String]) -> Color {
        Color(uiColor(for: characterName, allCharacters: allCharacters))
    }
}
