import SwiftUI

struct CharacterDetailView: View {
    let character: ScriptCharacter
    let parseResult: ScriptParseResult
    let onJumpToPage: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    private var turns: [ScriptDialogueTurn] {
        parseResult.dialogueTurns.filter { $0.characterName == character.name }
    }

    private var filteredTurns: [ScriptDialogueTurn] {
        guard !searchQuery.isEmpty else { return turns }
        let q = searchQuery.lowercased()
        return turns.filter {
            $0.dialogue.lowercased().contains(q) ||
            ($0.parenthetical?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        List {
            Section {
                statsRow
            }

            Section("Dialogue") {
                if filteredTurns.isEmpty {
                    Text("No matches.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(filteredTurns) { turn in
                        Button {
                            onJumpToPage(turn.pageIndex)
                            dismiss()
                        } label: {
                            turnRow(turn)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchQuery, prompt: "Search lines…")
    }

    private var statsRow: some View {
        HStack(spacing: 20) {
            statCell(label: "Turns", value: "\(turns.count)")
            Divider().frame(height: 32)
            statCell(label: "First page", value: character.firstPage.map { "p\($0 + 1)" } ?? "—")
            Divider().frame(height: 32)
            statCell(label: "Words (est.)", value: "\(estimatedWordCount)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).fontWeight(.semibold)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var estimatedWordCount: Int {
        turns.reduce(0) { $0 + $1.dialogue.split(separator: " ").count }
    }

    private func turnRow(_ turn: ScriptDialogueTurn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let qualifier = turn.qualifierSummary {
                    Text(qualifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Turn \(turn.sequenceIndex + 1) · p\(turn.pageIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let parenthetical = turn.parenthetical, !parenthetical.isEmpty {
                Text(parenthetical)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }

            Text(turn.dialogue)
                .font(.body)
                .lineLimit(4)
        }
        .padding(.vertical, 3)
    }
}
