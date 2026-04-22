import SwiftData
import SwiftUI

enum NotesGrouping: String, CaseIterable {
    case all    = "All"
    case script = "By Script"
    case tag    = "By Tag"
}

struct NotesView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \ScriptNote.updatedAt, order: .reverse) private var notes: [ScriptNote]
    @Query private var documents: [ScriptDocument]

    @State private var searchQuery = ""
    @State private var selectedTagFilter: NoteTag? = nil
    @State private var grouping: NotesGrouping = .all
    @State private var noteBeingEdited: ScriptNote?

    var body: some View {
        NavigationStack {
            List {
                if filteredNotes.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    switch grouping {
                    case .all:
                        ForEach(filteredNotes) { note in
                            noteListRow(for: note)
                        }
                    case .script:
                        scriptGroupedContent
                    case .tag:
                        tagGroupedContent
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Notes")
            .searchable(text: $searchQuery, prompt: "Search notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Group", selection: $grouping) {
                        ForEach(NotesGrouping.allCases, id: \.self) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    tagFilterMenu
                }
            }
            .sheet(item: $noteBeingEdited) { note in
                NoteEditView(note: note)
            }
        }
    }

    // MARK: - Grouped content

    @ViewBuilder
    private var scriptGroupedContent: some View {
        let grouped = Dictionary(grouping: filteredNotes) { note in
            document(for: note)?.title ?? "Unknown Script"
        }
        let sortedKeys = grouped.keys.sorted()
        ForEach(sortedKeys, id: \.self) { title in
            let sectionNotes = grouped[title] ?? []
            Section {
                ForEach(sectionNotes) { note in
                    noteListRow(for: note)
                }
            } header: {
                groupHeader(title: title, count: sectionNotes.count)
            }
        }
    }

    @ViewBuilder
    private var tagGroupedContent: some View {
        let grouped = Dictionary(grouping: filteredNotes) { note in
            note.tag?.rawValue ?? "Untagged"
        }
        let order = NoteTag.allCases.map(\.rawValue) + ["Untagged"]
        let sortedKeys = order.filter { grouped[$0] != nil }
        ForEach(sortedKeys, id: \.self) { tagName in
            let sectionNotes = grouped[tagName] ?? []
            Section {
                ForEach(sectionNotes) { note in
                    noteListRow(for: note)
                }
            } header: {
                groupHeader(title: tagName, count: sectionNotes.count)
            }
        }
    }

    private func groupHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Text("\(count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Note Row

    @ViewBuilder
    private func noteListRow(for note: ScriptNote) -> some View {
        let doc = document(for: note)
        Group {
            if let doc {
                NavigationLink {
                    ReaderSplitView(
                        document: doc,
                        initialJumpToPage: note.pageIndex,
                        initialPracticeTurnSequenceIndex: note.dialogueTurnSequenceIndex
                    )
                } label: {
                    noteRow(for: note, documentTitle: doc.title)
                }
            } else {
                noteRow(for: note, documentTitle: "Missing Script")
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                context.delete(note)
                try? context.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func noteRow(for note: ScriptNote, documentTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(documentTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let tag = note.tag {
                    tagBadge(tag)
                }
            }

            if let name = note.anchoredCharacterName, !name.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name).font(.headline).foregroundStyle(.orange)
                    if let q = note.anchoredQualifier, !q.isEmpty {
                        Text(q).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Text(note.text)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(4)

            if let snippet = note.anchoredDialogueSnippet, !snippet.isEmpty {
                Text("Cue: \(snippet)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let turn = note.dialogueTurnSequenceIndex { Text("Turn \(turn + 1)") }
                Text("Page \(note.pageIndex + 1)")
                Spacer()
                Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hoverEffect(.lift)
    }

    private func tagBadge(_ tag: NoteTag) -> some View {
        HStack(spacing: 3) {
            Image(systemName: tag.icon).font(.caption2)
            Text(tag.rawValue).font(.caption2).fontWeight(.medium)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(tag.color.opacity(0.15))
        .foregroundStyle(tag.color)
        .clipShape(Capsule())
    }

    // MARK: - Filtering

    private var filteredNotes: [ScriptNote] {
        notes.filter { note in
            let matchesTag = selectedTagFilter == nil || note.tag == selectedTagFilter
            let matchesSearch = searchQuery.isEmpty || noteMatchesSearch(note)
            return matchesTag && matchesSearch
        }
    }

    private func noteMatchesSearch(_ note: ScriptNote) -> Bool {
        let q = searchQuery.lowercased()
        return note.text.lowercased().contains(q)
            || (note.anchoredCharacterName?.lowercased().contains(q) ?? false)
            || (note.anchoredDialogueSnippet?.lowercased().contains(q) ?? false)
    }

    private var tagFilterMenu: some View {
        Menu {
            Button {
                selectedTagFilter = nil
            } label: {
                Label("All Notes", systemImage: selectedTagFilter == nil ? "checkmark" : "note.text")
            }
            Divider()
            ForEach(NoteTag.allCases) { tag in
                Button {
                    selectedTagFilter = selectedTagFilter == tag ? nil : tag
                } label: {
                    Label(tag.rawValue, systemImage: selectedTagFilter == tag ? "checkmark" : tag.icon)
                }
            }
        } label: {
            Image(systemName: selectedTagFilter != nil
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .foregroundStyle(selectedTagFilter != nil ? .orange : .primary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text").font(.largeTitle).foregroundStyle(.secondary)
            Text(searchQuery.isEmpty && selectedTagFilter == nil
                ? "No notes yet.\nCreate notes from Practice mode while rehearsing."
                : "No notes match your search or filter.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func document(for note: ScriptNote) -> ScriptDocument? {
        documents.first { $0.id == note.documentId }
    }
}

// MARK: - Edit Sheet

private struct NoteEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let note: ScriptNote
    @State private var text: String
    @State private var selectedTag: NoteTag?

    init(note: ScriptNote) {
        self.note = note
        _text = State(initialValue: note.text)
        _selectedTag = State(initialValue: note.tag)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    tagCard
                    noteCard
                    if let character = note.anchoredCharacterName, !character.isEmpty {
                        anchoredCard(character: character)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Cards

    private var tagCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Tag")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteTag.allCases) { tag in
                        Button {
                            selectedTag = selectedTag == tag ? nil : tag
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: tag.icon).font(.caption)
                                Text(tag.rawValue).font(.caption).fontWeight(.medium)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selectedTag == tag ? tag.color : tag.color.opacity(0.12))
                            .foregroundStyle(selectedTag == tag ? .white : tag.color)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Note")

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }

    private func anchoredCard(character: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Anchored to")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(character)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }

                if let snippet = note.anchoredDialogueSnippet {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private func save() {
        note.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        note.tag = selectedTag
        note.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}
