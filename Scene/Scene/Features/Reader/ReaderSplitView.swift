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
                // Index status row
                if vm.isParsing {
                    HStack {
                        ProgressView().scaleEffect(0.75)
                        Text("Indexing…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let at = vm.indexedAt {
                    Label("Indexed \(at.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .listRowBackground(Color.clear)
                }

                Section("Scenes") {
                    if vm.parseResult == nil && !vm.isParsing {
                        emptyIndexState
                    } else if let parseResult = vm.parseResult, parseResult.scenes.isEmpty {
                        Text("No scene headings detected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.parseResult?.scenes ?? []) { scene in
                            if let parseResult = vm.parseResult {
                                NavigationLink {
                                    SceneDetailView(scene: scene, parseResult: parseResult) { page in
                                        vm.jumpToPage = page
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("#\(scene.index) \(scene.heading)")
                                            .lineLimit(2)
                                        Text("Page \(scene.startPage + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }

                Section("Practice") {
                    if let parseResult = vm.parseResult {
                        if parseResult.dialogueTurns.isEmpty {
                            Text("No dialogue turns detected yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                isShowingPractice = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Open Practice Mode")
                                    Text("\(parseResult.dialogueTurns.count) dialogue turns ready")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button {
                                isShowingLyrics = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Lyrics Mode", systemImage: "text.alignleft")
                                    Text("Scrolling highlight, like Apple Music")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text("Build the index to unlock rehearsal mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Bookmarks") {
                    if bookmarks.isEmpty {
                        Text("No bookmarks yet. Tap the bookmark icon while reading.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                vm.jumpToPage = bookmark.pageIndex
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bookmark.fill")
                                        .foregroundStyle(.orange)
                                        .frame(width: 14)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bookmark.label ?? "Page \(bookmark.pageIndex + 1)")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        if bookmark.label != nil {
                                            Text("Page \(bookmark.pageIndex + 1)")
                                                .font(.caption)
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

                Section("Characters") {
                    if let parseResult = vm.parseResult, parseResult.characters.isEmpty {
                        Text("No screenplay character cues found in this PDF.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.parseResult?.characters ?? []) { c in
                            if let parseResult = vm.parseResult {
                                NavigationLink {
                                    CharacterDetailView(character: c, parseResult: parseResult) { page in
                                        vm.jumpToPage = page
                                    }
                                } label: {
                                    HStack {
                                        Text(c.name)
                                        Spacer()
                                        if let turnCount = dialogueTurnCounts[c.name] {
                                            Text("\(turnCount) turns")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let p = c.firstPage {
                                            Text("p\(p + 1)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
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
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Bookmark
                    Button {
                        bookmarkLabelDraft = ""
                        isShowingAddBookmark = true
                    } label: {
                        Image(systemName: "bookmark")
                    }

                    // Rehearse menu — only when dialogue is indexed
                    if let parseResult = vm.parseResult, !parseResult.dialogueTurns.isEmpty {
                        Menu {
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
                        } label: {
                            Label("Rehearse", systemImage: "theatermasks")
                        }
                    }

                    // Index button
                    if vm.isParsing {
                        ProgressView()
                    } else {
                        Menu {
                            Button {
                                Task { await vm.buildIndex(for: document, context: context, forceRebuild: true) }
                            } label: {
                                Label(vm.indexedAt != nil ? "Reindex Script" : "Build Index", systemImage: "wand.and.stars")
                            }
                        } label: {
                            Image(systemName: vm.indexedAt != nil ? "checkmark.circle" : "wand.and.stars")
                                .foregroundStyle(vm.indexedAt != nil ? .green : .secondary)
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

    private func autoOpenPracticeIfNeeded() {
        guard !hasAutoOpenedPractice,
              initialPracticeTurnSequenceIndex != nil,
              let parseResult = vm.parseResult,
              !parseResult.dialogueTurns.isEmpty else { return }

        hasAutoOpenedPractice = true
        isShowingPractice = true
    }

    private var emptyIndexState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Index not built yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Build Index") {
                Task { await vm.buildIndex(for: document, context: context, forceRebuild: true) }
            }
            .font(.caption)
        }
    }

    private var fileMissingPlaceholder: some View {
        ContentUnavailableView {
            Label("PDF Not Found", systemImage: "exclamationmark.triangle")
        } description: {
            Text(AppError.fileMissing.localizedDescription)
        }
    }
}
