import SwiftUI

struct GlossaryView: View {
    @StateObject private var store = GlossaryStore()
    @State private var query = ""

    private var filtered: [GlossaryTerm] {
        guard !query.isEmpty else { return store.terms }
        return store.terms.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.key.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(filtered) { t in
            VStack(alignment: .leading, spacing: 6) {
                Text(t.title).font(.headline)
                Text(t.description).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Glossary")
        .searchable(text: $query)
        .onAppear { store.load() }
    }
}
