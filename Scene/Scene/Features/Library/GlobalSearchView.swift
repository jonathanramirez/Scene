import SwiftData
import SwiftUI

struct GlobalSearchView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \ScriptDocument.createdAt, order: .reverse) private var documents: [ScriptDocument]
    @Query(sort: \ScriptNote.updatedAt, order: .reverse)     private var notes: [ScriptNote]
    @Query(sort: \ScriptBookmark.createdAt, order: .reverse) private var bookmarks: [ScriptBookmark]

    @State private var query = ""

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    emptyPrompt
                } else if hasNoResults {
                    noResults
                } else {
                    scriptSection
                    sceneSection
                    characterSection
                    noteSection
                    bookmarkSection
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Scripts, scenes, characters, notes…")
        }
    }

    // MARK: - Sections

    @ViewBuilder private var scriptSection: some View {
        let docs = matchingDocuments
        if !docs.isEmpty {
            Section {
                ForEach(docs) { doc in
                    NavigationLink { ScriptDetailView(document: doc) } label: {
                        resultRow(
                            icon: "books.vertical.fill", iconColor: doc.iconColor.color,
                            title: highlighted(doc.title),
                            subtitle: "\(doc.pageCount) pages · ~\(doc.estimatedMinutes) min",
                            badge: "Script", badgeColor: .blue
                        )
                    }
                }
            } header: { Text("Scripts") }
        }
    }

    @ViewBuilder private var sceneSection: some View {
        let items = matchingScenes
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.0.id) { scene, doc in
                    if let doc {
                        NavigationLink {
                            ReaderSplitView(document: doc, initialJumpToPage: scene.startPage)
                        } label: {
                            resultRow(
                                icon: "film.fill", iconColor: .purple,
                                title: highlighted("#\(scene.index) \(scene.heading)"),
                                subtitle: "\(doc.title) · p\(scene.startPage + 1)",
                                badge: "Scene", badgeColor: .purple
                            )
                        }
                    }
                }
            } header: { Text("Scenes") }
        }
    }

    @ViewBuilder private var characterSection: some View {
        let items = matchingCharacters
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.0.id) { character, doc, turnCount in
                    if let doc, let parseResult = loadedParseResult(doc) {
                        NavigationLink {
                            CharacterDetailView(character: character, parseResult: parseResult) { page in
                                // Jump handled inside CharacterDetailView
                                _ = page
                            }
                        } label: {
                            resultRow(
                                icon: "person.fill", iconColor: .orange,
                                title: highlighted(character.name),
                                subtitle: "\(doc.title) · \(turnCount) turns",
                                badge: "Character", badgeColor: .orange
                            )
                        }
                    }
                }
            } header: { Text("Characters") }
        }
    }

    @ViewBuilder private var noteSection: some View {
        let items = matchingNotes
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.0.id) { note, doc in
                    if let doc {
                        NavigationLink {
                            ReaderSplitView(
                                document: doc,
                                initialJumpToPage: note.pageIndex,
                                initialPracticeTurnSequenceIndex: note.dialogueTurnSequenceIndex
                            )
                        } label: {
                            noteRow(note, doc: doc)
                        }
                    } else {
                        noteRow(note, doc: nil)
                    }
                }
            } header: { Text("Notes") }
        }
    }

    @ViewBuilder private var bookmarkSection: some View {
        let items = matchingBookmarks
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.0.id) { bookmark, doc in
                    if let doc {
                        NavigationLink {
                            ReaderSplitView(document: doc, initialJumpToPage: bookmark.pageIndex)
                        } label: {
                            resultRow(
                                icon: "bookmark.fill", iconColor: .orange,
                                title: highlighted(bookmark.label ?? "Page \(bookmark.pageIndex + 1)"),
                                subtitle: "\(doc.title) · p\(bookmark.pageIndex + 1)",
                                badge: "Bookmark", badgeColor: .orange
                            )
                        }
                    }
                }
            } header: { Text("Bookmarks") }
        }
    }

    // MARK: - Rows

    private func resultRow(
        icon: String,
        iconColor: Color,
        title: AttributedString,
        subtitle: String,
        badge: String,
        badgeColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    typeBadge(badge, color: badgeColor)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func noteRow(_ note: ScriptNote, doc: ScriptDocument?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.green)
                .frame(width: 28, height: 28)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                if let character = note.anchoredCharacterName, !character.isEmpty {
                    Text(character)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
                Text(highlighted(note.text))
                    .font(.subheadline)
                    .lineLimit(2)
                HStack {
                    Text("\(doc?.title ?? "Unknown") · p\(note.pageIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    typeBadge("Note", color: .green)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func typeBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Highlighted text

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let q = query.lowercased()
        guard !q.isEmpty else { return attributed }
        var start = attributed.startIndex
        while start < attributed.endIndex {
            guard let range = attributed[start...].range(of: q, options: .caseInsensitive) else { break }
            attributed[range].backgroundColor = .orange.opacity(0.25)
            attributed[range].foregroundColor = .orange
            start = range.upperBound
        }
        return attributed
    }

    // MARK: - Filtering

    private var hasNoResults: Bool {
        matchingDocuments.isEmpty &&
        matchingScenes.isEmpty &&
        matchingCharacters.isEmpty &&
        matchingNotes.isEmpty &&
        matchingBookmarks.isEmpty
    }

    private var matchingDocuments: [ScriptDocument] {
        let q = query.lowercased()
        return documents.filter { $0.title.lowercased().contains(q) }
    }

    private var matchingScenes: [(ScriptScene, ScriptDocument?)] {
        let q = query.lowercased()
        return documents.flatMap { doc -> [(ScriptScene, ScriptDocument?)] in
            guard let cached = ParseCacheService.load(documentId: doc.id, context: context) else { return [] }
            return cached.result.scenes
                .filter { $0.heading.lowercased().contains(q) }
                .map { ($0, doc) }
        }
    }

    private var matchingCharacters: [(ScriptCharacter, ScriptDocument?, Int)] {
        let q = query.lowercased()
        return documents.flatMap { doc -> [(ScriptCharacter, ScriptDocument?, Int)] in
            guard let cached = ParseCacheService.load(documentId: doc.id, context: context) else { return [] }
            let turnCounts = Dictionary(grouping: cached.result.dialogueTurns, by: \.characterName)
                .mapValues(\.count)
            return cached.result.characters
                .filter { $0.name.lowercased().contains(q) }
                .map { ($0, doc, turnCounts[$0.name] ?? 0) }
        }
    }

    private var matchingNotes: [(ScriptNote, ScriptDocument?)] {
        let q = query.lowercased()
        return notes
            .filter {
                $0.text.lowercased().contains(q) ||
                ($0.anchoredCharacterName?.lowercased().contains(q) ?? false) ||
                ($0.anchoredDialogueSnippet?.lowercased().contains(q) ?? false)
            }
            .map { note in (note, documents.first { $0.id == note.documentId }) }
    }

    private var matchingBookmarks: [(ScriptBookmark, ScriptDocument?)] {
        let q = query.lowercased()
        return bookmarks
            .filter { ($0.label ?? "").lowercased().contains(q) }
            .map { bookmark in (bookmark, documents.first { $0.id == bookmark.documentId }) }
    }

    private func loadedParseResult(_ doc: ScriptDocument) -> ScriptParseResult? {
        ParseCacheService.load(documentId: doc.id, context: context)?.result
    }

    // MARK: - Empty states

    private var emptyPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Search across your library")
                    .font(.headline)
                Text("Scenes, characters, notes, bookmarks and script titles.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowBackground(Color.clear)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
            Text("No results for \"\(query)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowBackground(Color.clear)
    }
}
