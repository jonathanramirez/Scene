import SwiftUI
import SwiftData

struct NotesView: View {
    @Query(sort: \ScriptNote.updatedAt, order: .reverse) private var notes: [ScriptNote]
    @Query private var documents: [ScriptDocument]

    var body: some View {
        NavigationStack {
            List {
                ForEach(notes) { n in
                    if let document = document(for: n) {
                        NavigationLink {
                            ReaderSplitView(
                                document: document,
                                initialJumpToPage: n.pageIndex,
                                initialPracticeTurnSequenceIndex: n.dialogueTurnSequenceIndex
                            )
                        } label: {
                            noteRow(for: n, documentTitle: document.title)
                        }
                    } else {
                        noteRow(for: n, documentTitle: "Missing Script")
                    }
                }
            }
            .navigationTitle("Notes")
        }
    }

    @ViewBuilder
    private func noteRow(for note: ScriptNote, documentTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(documentTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let anchoredCharacterName = note.anchoredCharacterName, !anchoredCharacterName.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(anchoredCharacterName)
                        .font(.headline)

                    if let anchoredQualifier = note.anchoredQualifier, !anchoredQualifier.isEmpty {
                        Text(anchoredQualifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(note.text)
                .font(.body)

            if let anchoredDialogueSnippet = note.anchoredDialogueSnippet, !anchoredDialogueSnippet.isEmpty {
                Text("Cue: \(anchoredDialogueSnippet)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                if let dialogueTurnSequenceIndex = note.dialogueTurnSequenceIndex {
                    Text("Turn \(dialogueTurnSequenceIndex + 1)")
                }

                Text("Page \(note.pageIndex + 1)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func document(for note: ScriptNote) -> ScriptDocument? {
        documents.first { $0.id == note.documentId }
    }
}
