import SwiftUI
import SwiftData

struct NotesView: View {
    @Query(sort: \ScriptNote.updatedAt, order: .reverse) private var notes: [ScriptNote]

    var body: some View {
        NavigationStack {
            List {
                ForEach(notes) { n in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.text).lineLimit(2)
                        Text("Page \(n.pageIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Notes")
        }
    }
}
