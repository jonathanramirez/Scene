import SwiftUI

struct ScriptSearchView: View {
    let document: ScriptDocument
    let parseResult: ScriptParseResult
    let onJumpToPage: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    emptyPrompt
                } else if results.isEmpty {
                    noResults
                } else {
                    ForEach(results) { turn in
                        Button {
                            onJumpToPage(turn.pageIndex)
                            dismiss()
                        } label: {
                            resultRow(turn)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Search Script")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Character, dialogue…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var results: [ScriptDialogueTurn] {
        let q = query.lowercased()
        return parseResult.dialogueTurns.filter {
            $0.characterName.lowercased().contains(q) ||
            $0.dialogue.lowercased().contains(q) ||
            ($0.parenthetical?.lowercased().contains(q) ?? false)
        }
    }

    @ViewBuilder
    private func resultRow(_ turn: ScriptDialogueTurn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(turn.characterName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                if let qualifier = turn.qualifierSummary {
                    Text(qualifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("p\(turn.pageIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(highlightedText(turn.dialogue))
                .font(.subheadline)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    private func highlightedText(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let q = query.lowercased()
        guard !q.isEmpty else { return attributed }

        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex {
            let range = attributed[searchStart...].range(of: q, options: .caseInsensitive)
            guard let range else { break }
            attributed[range].backgroundColor = .orange.opacity(0.3)
            attributed[range].foregroundColor = .orange
            searchStart = range.upperBound
        }
        return attributed
    }

    private var emptyPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Search dialogue, characters, or parentheticals.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No matches for \"\(query)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}
