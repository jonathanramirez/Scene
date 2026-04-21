import SwiftUI

struct SceneDetailView: View {
    let scene: ScriptScene
    let parseResult: ScriptParseResult
    let onJumpToPage: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var turns: [ScriptDialogueTurn] {
        let end = scene.endPage ?? Int.max
        return parseResult.dialogueTurns.filter {
            $0.pageIndex >= scene.startPage && $0.pageIndex <= end
        }
    }

    private var charactersInScene: [String] {
        Array(Set(turns.map(\.characterName))).sorted()
    }

    var body: some View {
        List {
            Section {
                statsRow
            }

            if !charactersInScene.isEmpty {
                Section("Characters") {
                    ForEach(charactersInScene, id: \.self) { name in
                        let count = turns.filter { $0.characterName == name }.count
                        HStack {
                            Text(name).font(.subheadline)
                            Spacer()
                            Text("\(count) turn\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Dialogue") {
                if turns.isEmpty {
                    Text("No dialogue detected in this scene.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(turns) { turn in
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
        .navigationTitle("Scene \(scene.index)")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onJumpToPage(scene.startPage)
                    dismiss()
                } label: {
                    Label("Jump to Scene", systemImage: "arrow.right.circle")
                }
            }
        }
    }

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scene.heading)
                .font(.headline)
                .lineLimit(3)

            HStack(spacing: 16) {
                Label("Page \(scene.startPage + 1)", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let end = scene.endPage {
                    Label("\(end - scene.startPage + 1) pages", systemImage: "ruler")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label("\(turns.count) turns", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func turnRow(_ turn: ScriptDialogueTurn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(turn.characterName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                if let qualifier = turn.qualifierSummary {
                    Text(qualifier).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("p\(turn.pageIndex + 1)").font(.caption2).foregroundStyle(.tertiary)
            }
            if let paren = turn.parenthetical, !paren.isEmpty {
                Text(paren).font(.caption).italic().foregroundStyle(.secondary)
            }
            Text(turn.dialogue).font(.body).lineLimit(3)
        }
        .padding(.vertical, 3)
    }
}
