import SwiftData
import SwiftUI

struct ReaderSplitView: View {
    @Environment(\.modelContext) private var context

    let document: ScriptDocument
    let initialJumpToPage: Int?
    let initialPracticeTurnSequenceIndex: Int?

    @Environment(ScriptSessionStore.self) private var sessionStore
    @StateObject private var vm = ReaderSplitViewModel()
    @State private var isShowingPractice = false
    @State private var isShowingLyrics = false
    @State private var isShowingSearch = false
    @State private var hasAppliedInitialNavigation = false
    @State private var hasAutoOpenedPractice = false
    @State private var currentPageIndex = 0
    @State private var isShowingAddBookmark = false
    @State private var bookmarkLabelDraft = ""
    @State private var selectedCharacterForDetail: ScriptCharacter? = nil

    @Query(sort: \ScriptBookmark.createdAt, order: .reverse)
    private var allBookmarks: [ScriptBookmark]

    private var bookmarks: [ScriptBookmark] {
        allBookmarks.filter { $0.documentId == document.id }
    }

    init(document: ScriptDocument, initialJumpToPage: Int? = nil, initialPracticeTurnSequenceIndex: Int? = nil) {
        self.document = document
        self.initialJumpToPage = initialJumpToPage
        self.initialPracticeTurnSequenceIndex = initialPracticeTurnSequenceIndex
    }

    var body: some View {
        NavigationSplitView {
            List {
                // ── Rehearse cards ─────────────────────────────────────
                if let parseResult = vm.parseResult, !parseResult.dialogueTurns.isEmpty {
                    Section {
                        HStack(spacing: 10) {
                            rehearseCard(
                                icon: "mic.fill", label: "Practice", tint: .orange
                            ) { isShowingPractice = true }

                            rehearseCard(
                                icon: "text.alignleft", label: "Lyrics", tint: .purple
                            ) { isShowingLyrics = true }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)

                        Text("\(parseResult.dialogueTurns.count) turns · \(filteredCharacters.count) characters")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } header: {
                        Text("Rehearse")
                    }
                } else if vm.parseResult == nil && !vm.isParsing {
                    Section {
                        Button {
                            Task { await vm.buildIndex(for: document, context: context, forceRebuild: true) }
                        } label: {
                            Label("Build Index to Rehearse", systemImage: "wand.and.stars")
                        }
                        .font(.subheadline)
                    }
                }

                // ── Scenes ─────────────────────────────────────────────
                Section {
                    if vm.isParsing {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.75)
                            Text("Indexing…").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let parseResult = vm.parseResult {
                        if parseResult.scenes.isEmpty {
                            Text("No scene headings found.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(parseResult.scenes) { scene in
                                Button {
                                    vm.jumpToPage = scene.startPage
                                } label: {
                                    HStack(spacing: 0) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("#\(scene.index) \(scene.heading)")
                                                .font(.subheadline)
                                                .lineLimit(2)
                                                .foregroundStyle(.primary)
                                            Text("p\(scene.startPage + 1)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Non-standard format hint
                        if parseResult.scenes.isEmpty || parseResult.dialogueTurns.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange).font(.caption2)
                                Text("This PDF may not follow standard screenplay format.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(Color.orange.opacity(0.06))
                        }
                    }
                } header: {
                    HStack {
                        Text("Scenes")
                        Spacer()
                        if vm.isParsing {
                            ProgressView().scaleEffect(0.6)
                        } else if vm.indexedAt != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption2)
                        }
                    }
                }

                // ── Characters ────────────────────────────────────────
                if !filteredCharacters.isEmpty {
                    Section {
                        ForEach(filteredCharacters) { c in
                            HStack(spacing: 0) {
                                // Tap row → jump PDF to character's first page
                                Button {
                                    if let page = c.firstPage { vm.jumpToPage = page }
                                } label: {
                                    HStack {
                                        Text(c.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if let turns = dialogueTurnCounts[c.name] {
                                            Text("\(turns)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 1)
                                }
                                .buttonStyle(.plain)

                                // Info button → opens CharacterDetailView as sheet
                                if vm.parseResult != nil {
                                    Button {
                                        selectedCharacterForDetail = c
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .padding(.leading, 10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Characters")
                            Spacer()
                            Text("\(filteredCharacters.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Bookmarks (only when non-empty) ───────────────────
                if !bookmarks.isEmpty {
                    Section("Bookmarks") {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                vm.jumpToPage = bookmark.pageIndex
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bookmark.fill")
                                        .foregroundStyle(.orange)
                                        .frame(width: 14)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(bookmark.label ?? "Page \(bookmark.pageIndex + 1)")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        if bookmark.label != nil {
                                            Text("p\(bookmark.pageIndex + 1)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    context.delete(bookmark)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(document.title)
        } detail: {
            if let url = document.resolvedFileURL, FileManager.default.fileExists(atPath: url.path) {
                readerDetail
            } else {
                fileMissingPlaceholder
            }
        }
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
            if let parseResult = vm.parseResult {
                ScriptSearchView(document: document, parseResult: parseResult) { page in
                    vm.jumpToPage = page
                }
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
        ReaderView(document: document, jumpToPage: $vm.jumpToPage, onPageChanged: { page in
                currentPageIndex = page
                sessionStore.session(for: document.id).currentPage = page
            })
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Bookmark
                    Button {
                        bookmarkLabelDraft = ""
                        isShowingAddBookmark = true
                    } label: {
                        Image(systemName: "bookmark")
                    }

                    // Rehearse menu — practice, lyrics, search + index management
                    Menu {
                        if let parseResult = vm.parseResult, !parseResult.dialogueTurns.isEmpty {
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

                            Button {
                                isShowingSearch = true
                            } label: {
                                Label("Search Script", systemImage: "magnifyingglass")
                            }

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

    private var dialogueTurnCounts: [String: Int] {
        guard let parseResult = vm.parseResult else { return [:] }
        return parseResult.dialogueTurns.reduce(into: [:]) { counts, turn in
            counts[turn.characterName, default: 0] += 1
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

    @ViewBuilder
    private func rehearseCard(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var fileMissingPlaceholder: some View {
        ContentUnavailableView {
            Label("PDF Not Found", systemImage: "exclamationmark.triangle")
        } description: {
            Text(AppError.fileMissing.localizedDescription)
        }
    }
}
