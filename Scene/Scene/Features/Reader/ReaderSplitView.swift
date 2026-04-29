import SwiftData
import SwiftUI

struct ReaderSplitView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let document: ScriptDocument
    let initialJumpToPage: Int?
    let initialPracticeTurnSequenceIndex: Int?

    @Environment(ScriptSessionStore.self) private var sessionStore
    @StateObject private var vm = ReaderSplitViewModel()
    @State private var isShowingPractice = false
    @State private var isShowingLyrics = false
    @State private var isShowingSearch = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var hasAppliedInitialNavigation = false
    @State private var hasAutoOpenedPractice = false
    @State private var currentPageIndex = 0
    @State private var isShowingAddBookmark = false
    @State private var bookmarkLabelDraft = ""
    @State private var isShowingAddNote = false
    @State private var noteDraft = ""
    @State private var selectedNoteTag: NoteTag?
    @State private var selectedCharacterForDetail: ScriptCharacter? = nil
    @State private var activeSearchHighlight: PDFSearchHighlight?
    @State private var isShowingPDFReadingControls = false
    @State private var isPDFReadingOverlayEnabled = false
    @State private var isPDFReadingMuteAll = false
    @State private var mutedPDFReadingCharacters: Set<String> = []

    @Query(sort: \ScriptBookmark.createdAt, order: .reverse)
    private var allBookmarks: [ScriptBookmark]

    @Query(sort: \ScriptNote.updatedAt, order: .reverse)
    private var allNotes: [ScriptNote]

    private var bookmarks: [ScriptBookmark] {
        allBookmarks.filter { $0.documentId == document.id }
    }

    private var notes: [ScriptNote] {
        allNotes.filter { $0.documentId == document.id }
    }

    init(document: ScriptDocument, initialJumpToPage: Int? = nil, initialPracticeTurnSequenceIndex: Int? = nil) {
        self.document = document
        self.initialJumpToPage = initialJumpToPage
        self.initialPracticeTurnSequenceIndex = initialPracticeTurnSequenceIndex
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            if let url = document.resolvedFileURL, FileManager.default.fileExists(atPath: url.path) {
                readerDetail
            } else {
                fileMissingPlaceholder
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if !hasAppliedInitialNavigation {
                vm.jumpToPage = initialJumpToPage
                hasAppliedInitialNavigation = true
            }

            await vm.buildIndex(for: document, context: context)
            restoreRehearsalState()
            autoOpenPracticeIfNeeded()
        }
        .onChange(of: vm.parseResult?.dialogueTurns.count ?? 0) { _, _ in
            autoOpenPracticeIfNeeded()
        }
        .sheet(isPresented: $isShowingPractice) {
            if let parseResult = vm.parseResult {
                PracticeSessionView(
                    document: document,
                    parseResult: parseResult,
                    initialFocusedTurnSequenceIndex: initialPracticeTurnSequenceIndex
                )
            }
        }
        .sheet(isPresented: $isShowingSearch) {
            ScriptSearchView(document: document) { match in
                activeSearchHighlight = PDFSearchHighlight(
                    query: match.query,
                    pageIndex: match.pageIndex,
                    occurrenceIndex: match.occurrenceIndex
                )
                vm.jumpToPage = match.pageIndex
            }
        }
        .sheet(isPresented: $isShowingPDFReadingControls) {
            if let parseResult = vm.parseResult {
                PDFReadingControlsView(
                    parseResult: parseResult,
                    isEnabled: $isPDFReadingOverlayEnabled,
                    isMuteAll: $isPDFReadingMuteAll,
                    mutedCharacters: $mutedPDFReadingCharacters
                )
            }
        }
        .sheet(item: $selectedCharacterForDetail) { character in
            if let parseResult = vm.parseResult {
                NavigationStack {
                    CharacterDetailView(character: character, parseResult: parseResult) { page in
                        vm.jumpToPage = page
                        selectedCharacterForDetail = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedCharacterForDetail = nil }
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingLyrics) {
            if let parseResult = vm.parseResult {
                LyricsPracticeView(document: document, parseResult: parseResult)
            }
        }
    }

    private var readerDetail: some View {
        ReaderView(
            document: document,
            dialogueTurns: vm.parseResult?.dialogueTurns ?? [],
            dialogueHighlightSettings: PDFDialogueHighlightSettings(
                isEnabled: isPDFReadingOverlayEnabled,
                mutedCharacters: mutedPDFReadingCharacters,
                isMuteAll: isPDFReadingMuteAll
            ),
            jumpToPage: $vm.jumpToPage,
            searchHighlight: $activeSearchHighlight,
            onPageChanged: { page in
            currentPageIndex = page
            sessionStore.session(for: document.id).currentPage = page
            }
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Close reader")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    noteDraft = ""
                    selectedNoteTag = nil
                    isShowingAddNote = true
                } label: {
                    Image(systemName: "note.text.badge.plus")
                }
                .accessibilityLabel("Add note")

                Button {
                    bookmarkLabelDraft = ""
                    isShowingAddBookmark = true
                } label: {
                    Image(systemName: "bookmark")
                }

                Menu {
                    if let parseResult = vm.parseResult, !parseResult.dialogueTurns.isEmpty {
                        Button {
                            isPDFReadingOverlayEnabled.toggle()
                            if isPDFReadingOverlayEnabled {
                                isPDFReadingMuteAll = false
                            }
                        } label: {
                            Label(
                                isPDFReadingOverlayEnabled ? "Hide PDF Reading Colors" : "Show PDF Reading Colors",
                                systemImage: "highlighter"
                            )
                        }

                        Button {
                            isShowingPDFReadingControls = true
                        } label: {
                            Label("PDF Reading Controls", systemImage: "slider.horizontal.3")
                        }

                        Divider()

                        Button {
                            isShowingPractice = true
                        } label: {
                            Label("Practice Mode", systemImage: "mic")
                        }

                        Button {
                            isShowingLyrics = true
                        } label: {
                            Label("Lyrics Mode", systemImage: "text.alignleft")
                        }

                        Divider()
                    }

                    Button {
                        isShowingSearch = true
                    } label: {
                        Label("Search Script", systemImage: "magnifyingglass")
                    }

                    if vm.parseResult?.dialogueTurns.isEmpty == false {
                        Divider()
                    }

                    if vm.isParsing {
                        Label("Indexing…", systemImage: "gearshape")
                    } else {
                        Button {
                            Task { await vm.buildIndex(for: document, context: context, forceRebuild: true) }
                        } label: {
                            Label(
                                vm.indexedAt != nil ? "Reindex Script" : "Build Index",
                                systemImage: "wand.and.stars"
                            )
                        }
                    }
                } label: {
                    if vm.isParsing {
                        ProgressView()
                    } else {
                        Label("Rehearse", systemImage: "theatermasks")
                            .symbolVariant(vm.indexedAt != nil ? .none : .none)
                    }
                }
            }
        }
        .alert("Add Bookmark", isPresented: $isShowingAddBookmark) {
            TextField("Label (optional)", text: $bookmarkLabelDraft)
            Button("Add") { saveBookmark() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Bookmarking page \(currentPageIndex + 1)")
        }
        .sheet(isPresented: $isShowingAddNote) {
            ReaderAddNoteView(
                pageIndex: currentPageIndex,
                text: $noteDraft,
                selectedTag: $selectedNoteTag,
                onCancel: {
                    isShowingAddNote = false
                },
                onSave: {
                    saveNote()
                }
            )
        }
    }

    private func saveBookmark() {
        let label = bookmarkLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = ScriptBookmark(
            documentId: document.id,
            pageIndex: currentPageIndex,
            label: label.isEmpty ? nil : label
        )
        context.insert(bookmark)
        try? context.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func saveNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let note = ScriptNote(
            documentId: document.id,
            pageIndex: currentPageIndex,
            text: trimmed,
            tag: selectedNoteTag,
            rectString: defaultNoteAnchorString(for: currentPageIndex)
        )
        context.insert(note)
        try? context.save()
        noteDraft = ""
        selectedNoteTag = nil
        isShowingAddNote = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func defaultNoteAnchorString(for pageIndex: Int) -> String {
        let pageNoteCount = notes.filter { $0.pageIndex == pageIndex }.count
        let y = min(0.14 + (Double(pageNoteCount % 6) * 0.08), 0.58)
        return String(format: "%.3f,%.3f", 0.88, y)
    }

    private var dialogueTurnCounts: [String: Int] {
        guard let parseResult = vm.parseResult else { return [:] }
        return parseResult.dialogueTurns.reduce(into: [:]) { counts, turn in
            counts[turn.characterName, default: 0] += 1
	}
}

private struct ReaderAddNoteView: View {
    @Environment(\.dismiss) private var dismiss

    let pageIndex: Int
    @Binding var text: String
    @Binding var selectedTag: NoteTag?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    tagCard
                    noteCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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
                                Image(systemName: tag.icon)
                                    .font(.caption)
                                Text(tag.rawValue)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
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
            ReaderSidebarSectionHeader("Page \(pageIndex + 1)")

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
}

private struct PDFReadingControlsView: View {
    @Environment(\.dismiss) private var dismiss

    let parseResult: ScriptParseResult
    @Binding var isEnabled: Bool
    @Binding var isMuteAll: Bool
    @Binding var mutedCharacters: Set<String>

    private var characters: [String] {
        let speakers = Set(parseResult.dialogueTurns.map(\.characterName))
        return parseResult.characters
            .map(\.name)
            .filter { speakers.contains($0) }
            .sorted()
    }

    private var turnCounts: [String: Int] {
        parseResult.dialogueTurns.reduce(into: [:]) { counts, turn in
            counts[turn.characterName, default: 0] += 1
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Highlight dialogue on PDF", isOn: $isEnabled)

                    Toggle("Mute all characters", isOn: $isMuteAll)
                        .disabled(!isEnabled)

                    HStack {
                        Button("Unmute All") {
                            mutedCharacters.removeAll()
                            isMuteAll = false
                            isEnabled = true
                        }
                        .buttonStyle(.bordered)

                        Button("Mute All") {
                            isMuteAll = true
                            isEnabled = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Muted characters are not colored on the PDF.")
                }

                Section("Characters") {
                    ForEach(characters, id: \.self) { character in
                        Toggle(isOn: binding(for: character)) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(PDFDialogueHighlightPalette.swiftUIColor(
                                        for: character,
                                        allCharacters: characters
                                    ))
                                    .frame(width: 14, height: 14)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(character)
                                        .font(.body.weight(.medium))

                                    Text("\(turnCounts[character, default: 0]) turns")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!isEnabled || isMuteAll)
                    }
                }
            }
            .navigationTitle("PDF Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for character: String) -> Binding<Bool> {
        Binding(
            get: { !mutedCharacters.contains(character) },
            set: { isVisible in
                isEnabled = true
                isMuteAll = false
                if isVisible {
                    mutedCharacters.remove(character)
                } else {
                    mutedCharacters.insert(character)
                }
            }
        )
    }
}

    /// Seeds the in-memory ScriptSessionState from the persisted ScriptReadingSession
    /// so the app remembers the last rehearsed character across app restarts.
    private func restoreRehearsalState() {
        let state = sessionStore.session(for: document.id)
        // Only restore when nothing is set yet (avoids stomping a fresh in-session pick)
        guard state.selectedCharacter == nil else { return }

        // Capture UUID into a plain local — required for #Predicate to work correctly
        let docID = document.id
        var descriptor = FetchDescriptor<ScriptReadingSession>(
            predicate: #Predicate { $0.documentId == docID }
        )
        descriptor.fetchLimit = 1
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]

        guard let saved = try? context.fetch(descriptor).first,
              let character = saved.selectedCharacter,
              !character.isEmpty else { return }

        state.selectedCharacter = character
    }

    private func autoOpenPracticeIfNeeded() {
        guard !hasAutoOpenedPractice,
              initialPracticeTurnSequenceIndex != nil,
              let parseResult = vm.parseResult,
              !parseResult.dialogueTurns.isEmpty else { return }

        hasAutoOpenedPractice = true
        isShowingPractice = true
    }

    /// Characters with at least one letter — filters out parser false-positives like "2." or "IV."
    private var filteredCharacters: [ScriptCharacter] {
        (vm.parseResult?.characters ?? []).filter { c in
            c.name.count >= 2 && c.name.contains(where: { $0.isLetter })
        }
    }

    private var fileMissingPlaceholder: some View {
        ContentUnavailableView {
            Label("PDF Not Found", systemImage: "exclamationmark.triangle")
        } description: {
            Text(AppError.fileMissing.localizedDescription)
        }
    }

    // MARK: - Sidebar content

    private var sidebarContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ReaderSidebarHeaderCard(
                    title: document.title,
                    currentPageIndex: currentPageIndex,
                    pageCount: document.pageCount,
                    currentScene: currentScene,
                    parseResult: vm.parseResult,
                    characterCount: filteredCharacters.count,
                    isParsing: vm.isParsing,
                    indexedAt: vm.indexedAt,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            columnVisibility = .detailOnly
                        }
                    }
                )

                ReaderSidebarQuickActions(
                    hasIndex: vm.parseResult?.dialogueTurns.isEmpty == false,
                    isParsing: vm.isParsing,
                    onPractice: { isShowingPractice = true },
                    onLyrics: { isShowingLyrics = true },
                    onSearch: { isShowingSearch = true },
                    onAddBookmark: {
                        bookmarkLabelDraft = ""
                        isShowingAddBookmark = true
                    },
                    onBuildIndex: {
                        Task { await vm.buildIndex(for: document, context: context, forceRebuild: true) }
                    }
                )

                ReaderSidebarSceneSection(
                    scenes: vm.parseResult?.scenes ?? [],
                    isParsing: vm.isParsing,
                    hasParseResult: vm.parseResult != nil,
                    currentSceneIndex: currentSceneIndex,
                    onJump: { vm.jumpToPage = $0 }
                )

                if !bookmarks.isEmpty {
                    ReaderSidebarBookmarkSection(
                        bookmarks: bookmarks,
                        onJump: { vm.jumpToPage = $0 },
                        onDelete: { bookmark in
                            context.delete(bookmark)
                            try? context.save()
                        }
                    )
                }

                if !filteredCharacters.isEmpty {
                    ReaderSidebarCharacterSection(
                        characters: filteredCharacters,
                        dialogueTurnCounts: dialogueTurnCounts,
                        hasParseResult: vm.parseResult != nil,
                        onJump: { vm.jumpToPage = $0 },
                        onInfo: { selectedCharacterForDetail = $0 }
                    )
                }

                if showFormatWarning {
                    ReaderSidebarWarningBanner(
                        message: "This PDF may not follow standard screenplay format. Some features may be limited."
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Current scene tracking

    private var currentScene: ScriptScene? {
        guard let scenes = vm.parseResult?.scenes, !scenes.isEmpty else { return nil }
        var result: ScriptScene? = nil
        for scene in scenes {
            if scene.startPage <= currentPageIndex {
                result = scene
            } else {
                break
            }
        }
        return result ?? scenes.first
    }

    private var currentSceneIndex: Int? {
        currentScene?.index
    }

    // MARK: Warning visibility

    private var showFormatWarning: Bool {
        guard let pr = vm.parseResult else { return false }
        return pr.scenes.isEmpty || pr.dialogueTurns.isEmpty
    }
}
