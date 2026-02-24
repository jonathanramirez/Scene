import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScriptDocument.createdAt, order: .reverse) private var docs: [ScriptDocument]
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(docs) { doc in
                    NavigationLink {
                        ReaderSplitView(document: doc)
                    } label: {
                        ScriptRowView(document: doc)
                    }
                }
            }
            .navigationTitle("Scene")
            .toolbar { ImportButton(isPresented: $isImporting) }
        }
    }
}
