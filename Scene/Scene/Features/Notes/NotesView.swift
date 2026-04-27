import SwiftData
import SwiftUI
import PDFKit

struct NotesView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \ScriptNote.updatedAt, order: .reverse) private var notes: [ScriptNote]
    @Query private var documents: [ScriptDocument]

    @State private var searchQuery = ""
    @State private var selectedTagFilter: NoteTag? = nil
    @State private var noteBeingEdited: ScriptNote?

    var body: some View {
        NavigationStack {
            ScrollView {
                if filteredNotes.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                        scriptGroupedContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Notes")
            .searchable(text: $searchQuery, prompt: "Search notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    tagFilterMenu
                }
            }
            .sheet(item: $noteBeingEdited) { note in
                NoteEditView(note: note, documentTitle: document(for: note)?.title ?? "Missing Script")
            }
        }
    }

    // MARK: - Grouped content

    @ViewBuilder
    private var scriptGroupedContent: some View {
        ForEach(noteSections, id: \.title) { section in
            Section {
                LazyVStack(spacing: 12) {
                    ForEach(section.notes) { note in
                        noteListRow(for: note)
                    }
                }
            } header: {
                groupHeader(title: section.title, count: section.notes.count)
            }
        }
    }

    private func groupHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(count == 1 ? "1 note" : "\(count) notes")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Note Row

    @ViewBuilder
    private func noteListRow(for note: ScriptNote) -> some View {
        let doc = document(for: note)
        Group {
            if let doc {
                NavigationLink {
                    NoteDetailView(note: note, document: doc)
                } label: {
                    noteRow(for: note, document: doc)
                }
                .buttonStyle(.plain)
            } else {
                noteRow(for: note, document: nil)
            }
        }
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
    private func noteRow(for note: ScriptNote, document: ScriptDocument?) -> some View {
        let progress = pageProgress(for: note, document: document)

        HStack(spacing: 16) {
            noteDocumentIcon

            VStack(alignment: .leading, spacing: 8) {
                Text(note.text)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    pill("Page \(note.pageIndex + 1)", foreground: .secondary, background: Color(.tertiarySystemFill))

                    if let tag = note.tag {
                        tagBadge(tag)
                    }

                    if let document, document.pageCount > 0 {
                        pill("\(document.pageCount) pages", foreground: .secondary, background: Color(.tertiarySystemFill))
                    }
                }

                HStack(spacing: 6) {
                    Text(rowContext(for: note))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("Page \(note.pageIndex + 1)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: max(0, proxy.size.width * progress))
                    }
                }
                .frame(height: 4)
            }

            Spacer(minLength: 0)

            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.orange)
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                context.delete(note)
                try? context.save()
            } label: {
                Label("Delete Note", systemImage: "trash")
            }
        }
    }

    private var noteDocumentIcon: some View {
        Image(systemName: "doc.text.fill")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .shadow(color: .blue.opacity(0.18), radius: 8, y: 4)
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

    private func pill(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
    }

    private func rowContext(for note: ScriptNote) -> String {
        if let name = note.anchoredCharacterName, !name.isEmpty {
            return name
        }

        return relativeUpdatedDate(for: note.updatedAt)
    }

    private func pageProgress(for note: ScriptNote, document: ScriptDocument?) -> Double {
        guard let document, document.pageCount > 0 else { return 0 }
        let rawProgress = Double(note.pageIndex + 1) / Double(document.pageCount)
        return min(max(rawProgress, 0), 1)
    }

    // MARK: - Filtering

    private struct NoteSection {
        let title: String
        let notes: [ScriptNote]
        let latestUpdatedAt: Date
    }

    private var noteSections: [NoteSection] {
        let grouped = Dictionary(grouping: filteredNotes) { note in
            document(for: note)?.title ?? "Unknown Script"
        }

        return grouped.map { title, notes in
            let sortedNotes = notes.sorted { $0.updatedAt > $1.updatedAt }
            return NoteSection(
                title: title,
                notes: sortedNotes,
                latestUpdatedAt: sortedNotes.first?.updatedAt ?? .distantPast
            )
        }
        .sorted { lhs, rhs in
            if lhs.latestUpdatedAt == rhs.latestUpdatedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.latestUpdatedAt > rhs.latestUpdatedAt
        }
    }

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
                .font(.title2)
                .foregroundStyle(selectedTagFilter != nil ? .blue : .primary)
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

    private func relativeUpdatedDate(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Updated today"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

// MARK: - Note Detail

private struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let note: ScriptNote
    let document: ScriptDocument

    @State private var noteBeingEdited: ScriptNote?
    @State private var thumbnail: UIImage?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                detailHeader
                pagePreviewCard
                noteTextCard
                actionRow
                metadataCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $noteBeingEdited) { note in
            NoteEditView(note: note, documentTitle: document.title)
        }
        .task(id: "\(document.id)-\(note.pageIndex)") {
            loadThumbnail()
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(document.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 10) {
                Text("Page \(note.pageIndex + 1)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if let tag = note.tag {
                    tagPill(tag)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var pagePreviewCard: some View {
        NavigationLink {
            ReaderSplitView(
                document: document,
                initialJumpToPage: note.pageIndex,
                initialPracticeTurnSequenceIndex: note.dialogueTurnSequenceIndex
            )
        } label: {
            HStack(alignment: .top, spacing: 22) {
                thumbnailView

                VStack(alignment: .leading, spacing: 10) {
                    Text("Page \(note.pageIndex + 1)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Tap to open in Reader")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Label("Open", systemImage: "arrow.up.forward.square")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 170)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
                .frame(width: 150, height: 170)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var noteTextCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NOTE")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Text(note.text)
                .font(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            NavigationLink {
                ReaderSplitView(
                    document: document,
                    initialJumpToPage: note.pageIndex,
                    initialPracticeTurnSequenceIndex: note.dialogueTurnSequenceIndex
                )
            } label: {
                Label("Open", systemImage: "book")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NoteActionButtonStyle(background: .blue, foreground: .white))

            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NoteActionButtonStyle(background: Color(.tertiarySystemFill), foreground: .blue))

            Button(role: .destructive) {
                context.delete(note)
                try? context.save()
                dismiss()
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NoteActionButtonStyle(background: .red.opacity(0.16), foreground: .red))
        }
    }

    private var metadataCard: some View {
        VStack(spacing: 0) {
            metadataRow(title: "Created", value: note.createdAt.formatted(date: .abbreviated, time: .shortened))
            Divider()
            metadataRow(title: "Updated", value: note.updatedAt.formatted(date: .abbreviated, time: .shortened))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.body)
        .padding(.vertical, 12)
    }

    private func tagPill(_ tag: NoteTag) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tag.icon).font(.caption)
            Text(tag.rawValue).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .foregroundStyle(tag.color)
        .background(tag.color.opacity(0.14), in: Capsule())
    }

    private func loadThumbnail() {
        guard let url = document.resolvedFileURL,
              let pdf = PDFDocument(url: url),
              let page = pdf.page(at: note.pageIndex)
        else { return }

        thumbnail = page.thumbnail(of: CGSize(width: 300, height: 340), for: .mediaBox)
    }
}

private struct NoteActionButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, 18)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

// MARK: - Edit Sheet

private struct NoteEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let note: ScriptNote
    let documentTitle: String
    @State private var text: String
    @State private var selectedTag: NoteTag?

    init(note: ScriptNote, documentTitle: String) {
        self.note = note
        self.documentTitle = documentTitle
        _text = State(initialValue: note.text)
        _selectedTag = State(initialValue: note.tag)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    contextCard
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

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(documentTitle)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label("Page \(note.pageIndex + 1)", systemImage: "doc.text")
                if let turn = note.dialogueTurnSequenceIndex {
                    Text("Turn \(turn + 1)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

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
                .frame(minHeight: 120)
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
