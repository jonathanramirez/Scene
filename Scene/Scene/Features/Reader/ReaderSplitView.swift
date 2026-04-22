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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }

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
                    indexedAt: vm.indexedAt
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
