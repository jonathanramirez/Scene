import PDFKit
import SwiftData
import SwiftUI

struct ScriptDetailView: View {
    @Environment(\.modelContext) private var context

    let document: ScriptDocument

    @Query(sort: \ScriptReadingSession.updatedAt, order: .reverse)
    private var allSessions: [ScriptReadingSession]

    @Query(sort: \ScriptBookmark.createdAt, order: .reverse)
    private var allBookmarks: [ScriptBookmark]

    @State private var thumbnail: UIImage?
    @State private var selectedMode: ReadingMode = .firstRead

    // Parse state
    @State private var parseResult: ScriptParseResult?
    @State private var isParsing = false
    @State private var indexedAt: Date? = nil
    @State private var parseError: String?

    // Modals
    @State private var isShowingPractice = false
    @State private var isShowingLyrics   = false

    private var session: ScriptReadingSession? {
        allSessions.first { $0.documentId == document.id }
    }

    private var bookmarks: [ScriptBookmark] {
        allBookmarks.filter { $0.documentId == document.id }
    }

    private var initialJumpPage: Int? {
        guard let session, session.progress > 0 else { return nil }
        return session.lastPageIndex
    }

    var body: some View {
        Form {
            headerSection
            progressSection
            modeSection
            actionsSection

            if !bookmarks.isEmpty {
                bookmarksSection
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadThumbnail()
            if let session { selectedMode = session.mode }
            await buildIndex()
        }
        .onChange(of: selectedMode) { _, newMode in
            persistMode(newMode)
        }
        .alert("Index Failed", isPresented: Binding(
            get: { parseError != nil },
            set: { if !$0 { parseError = nil } }
        )) {
            Button("Retry") { Task { await buildIndex(force: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(parseError ?? AppError.parseFailed.localizedDescription)
        }
        .sheet(isPresented: $isShowingPractice) {
            if let parseResult {
                PracticeSessionView(document: document, parseResult: parseResult)
            }
        }
        .fullScreenCover(isPresented: $isShowingLyrics) {
            if let parseResult {
                LyricsPracticeView(document: document, parseResult: parseResult)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                thumbnailView
                    .frame(width: 80, height: 110)

                VStack(alignment: .leading, spacing: 6) {
                    Text(document.title)
                        .font(.headline)
                        .lineLimit(3)

                    Label("\(document.pageCount) pages", systemImage: "doc.text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label("~\(document.estimatedMinutes) min", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(document.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    indexStatusLabel
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .overlay {
                    Image(systemName: "doc.text.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var progressSection: some View {
        Section("Reading Progress") {
            if let session, session.progress > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: session.progress)
                        .tint(.orange)

                    HStack {
                        Text("Page \(session.lastPageIndex + 1) of \(document.pageCount)")
                        Spacer()
                        Text("\(Int(session.progress * 100))% read")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("Not started yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Reading Mode", selection: $selectedMode) {
                Text("First Read").tag(ReadingMode.firstRead)
                Text("Second Read").tag(ReadingMode.secondRead)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            Text(selectedMode == .firstRead
                ? "Focus on story flow and characters. Minimal interruptions."
                : "Analyze structure, dialogue, and themes. Take deeper notes."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("Reading Mode")
        }
    }

    private var actionsSection: some View {
        Section {
            // PDF missing warning
            if document.resolvedFileURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
                Label(AppError.fileMissing.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            // Reading
            NavigationLink {
                ReaderSplitView(document: document, initialJumpToPage: initialJumpPage)
            } label: {
                Label(
                    (session?.progress ?? 0) > 0 ? "Continue Reading" : "Open Reader",
                    systemImage: (session?.progress ?? 0) > 0 ? "book.fill" : "book"
                )
                .foregroundStyle(.orange)
            }

            // Practice / Lyrics
            if isParsing {
                HStack {
                    Label("Indexing…", systemImage: "gearshape")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView().scaleEffect(0.8)
                }
            } else if let parseError {
                HStack {
                    Label("Index failed", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Retry") { Task { await buildIndex(force: true) } }
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                Text(parseError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let parseResult, !parseResult.dialogueTurns.isEmpty {
                Button { isShowingPractice = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Practice", systemImage: "mic")
                        Text(indexStats(parseResult)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { isShowingLyrics = true } label: {
                    Label("Lyrics Mode", systemImage: "text.alignleft")
                }
            } else if parseResult == nil {
                Button { Task { await buildIndex() } } label: {
                    Label("Build Index for Practice", systemImage: "wand.and.stars")
                }
                .foregroundStyle(.secondary)
            } else {
                Label("No dialogue detected in this PDF", systemImage: "mic.slash")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            // Annotate
            NavigationLink {
                ReaderSplitView(document: document, initialJumpToPage: nil)
            } label: {
                Label("Annotate & Draw", systemImage: "pencil.and.list.clipboard")
            }

            // Coverage
            NavigationLink {
                CoverageView(document: document)
            } label: {
                Label("Coverage", systemImage: "doc.text.magnifyingglass")
            }
        } header: {
            Text("Actions")
        }
    }

    private var bookmarksSection: some View {
        Section("Bookmarks (\(bookmarks.count))") {
            ForEach(bookmarks) { bookmark in
                NavigationLink {
                    ReaderSplitView(document: document, initialJumpToPage: bookmark.pageIndex)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bookmark.label ?? "Page \(bookmark.pageIndex + 1)")
                                .font(.subheadline)
                            if bookmark.label != nil {
                                Text("Page \(bookmark.pageIndex + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(bookmarks[i]) }
                try? context.save()
            }
        }
    }

    // MARK: - Helpers

    private func loadThumbnail() async {
        // Show cached version instantly if available
        thumbnail = ThumbnailCacheService.cached(for: document.id.uuidString)
        guard let url = document.resolvedFileURL else { return }
        // Generate (or retrieve from disk) on a background thread
        if let image = await ThumbnailCacheService.generate(pdfURL: url, documentId: document.id.uuidString) {
            thumbnail = image
        }
    }

    private func buildIndex(force: Bool = false) async {
        guard !isParsing else { return }

        // Check cache first
        if !force, let cached = ParseCacheService.load(documentId: document.id, context: context) {
            parseResult = cached.result
            indexedAt = cached.indexedAt
            parseError = nil
            return
        }

        guard let url = document.resolvedFileURL else {
            parseError = AppError.fileMissing.localizedDescription
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            parseError = AppError.fileMissing.localizedDescription
            return
        }

        isParsing = true
        parseError = nil
        defer { isParsing = false }
        do {
            let result = try await ScriptParser().parse(url: url)
            parseResult = result
            ParseCacheService.save(result, documentId: document.id, context: context)
            indexedAt = Date()
        } catch {
            parseResult = nil
            parseError = error.localizedDescription
        }
    }

    private func persistMode(_ mode: ReadingMode) {
        if let session {
            session.mode = mode
            session.updatedAt = Date()
        } else if mode != .firstRead {
            let s = ScriptReadingSession(documentId: document.id, mode: mode)
            context.insert(s)
        }
        try? context.save()
    }

    // MARK: - Index helpers

    @ViewBuilder
    private var indexStatusLabel: some View {
        if isParsing {
            Label("Indexing…", systemImage: "gearshape")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if let at = indexedAt {
            Label("Indexed \(at.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(.green)
        } else {
            Label("Not indexed", systemImage: "circle.dashed")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func indexStats(_ result: ScriptParseResult) -> String {
        let scenes = result.scenes.count
        let chars  = result.characters.count
        let turns  = result.dialogueTurns.count
        return "\(turns) turns · \(chars) characters · \(scenes) scenes"
    }
}
