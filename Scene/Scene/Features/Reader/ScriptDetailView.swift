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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                heroCard
                if pdfIsMissing {
                    missingPDFBanner
                }
                progressCard
                readingModeCard
                indexStatusCard
                actionsGrid
                coverageCard
                if !bookmarks.isEmpty {
                    bookmarksCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Hero

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 16) {
            thumbnailView
                .frame(width: 88, height: 120)

            VStack(alignment: .leading, spacing: 8) {
                Text(document.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    metaChip(icon: "doc.text", text: "\(document.pageCount) pages")
                    metaChip(icon: "clock", text: "~\(document.estimatedMinutes) min")
                }

                Text(document.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    // MARK: - Missing PDF banner

    private var pdfIsMissing: Bool {
        document.resolvedFileURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true
    }

    private var missingPDFBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text("PDF not found")
                    .font(.subheadline.weight(.semibold))
                Text(AppError.fileMissing.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
    }

    // MARK: - Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Reading Progress")
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                if let session, session.progress > 0 {
                    ProgressView(value: session.progress).tint(.orange)
                    HStack {
                        Text("Page \(session.lastPageIndex + 1) of \(document.pageCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(session.progress * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 8) {
                        statPill("\(selectedMode == .firstRead ? "1st" : "2nd") read", color: .blue)
                        statPill("~\(remainingMinutes) min left", color: .orange)
                    }
                } else {
                    Text("Not started yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        statPill("\(document.pageCount) pages", color: .blue)
                        statPill("~\(document.estimatedMinutes) min", color: .orange)
                    }
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

    // MARK: - Reading Mode

    private var readingModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Reading Mode")

            VStack(alignment: .leading, spacing: 10) {
                Picker("Reading Mode", selection: $selectedMode) {
                    Text("First Read").tag(ReadingMode.firstRead)
                    Text("Second Read").tag(ReadingMode.secondRead)
                }
                .pickerStyle(.segmented)

                Text(selectedMode == .firstRead
                    ? "Focus on story flow and characters. Minimal interruptions."
                    : "Analyze structure, dialogue, and themes. Take deeper notes."
                )
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
    }

    // MARK: - Index

    private var indexStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Index")

            HStack(spacing: 12) {
                Image(systemName: indexStatusIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(indexStatusColor)
                    .frame(width: 36, height: 36)
                    .background(indexStatusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(indexStatusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(indexStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isParsing {
                    ProgressView().scaleEffect(0.85)
                } else {
                    Button(indexedAt == nil ? "Build" : "Refresh") {
                        ReaderSidebarHaptic.fire(.light)
                        Task { await buildIndex(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
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

    // MARK: - Actions grid

    private var actionsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Open")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                spacing: 10
            ) {
                openReaderCard
                annotateCard
                practiceCard
                lyricsCard
            }
        }
    }

    private var openReaderCard: some View {
        let hasProgress = (session?.progress ?? 0) > 0
        return NavigationLink {
            ReaderSplitView(document: document, initialJumpToPage: initialJumpPage)
        } label: {
            actionCardContent(
                icon: hasProgress ? "book.fill" : "book",
                label: hasProgress ? "Continue" : "Open Reader",
                sublabel: hasProgress ? "Page \((session?.lastPageIndex ?? 0) + 1)" : nil,
                tint: .orange,
                filled: true
            )
            .hoverEffect(.lift)
        }
        .buttonStyle(PressableCardStyle())
    }

    private var annotateCard: some View {
        NavigationLink {
            ReaderSplitView(document: document, initialJumpToPage: nil)
        } label: {
            actionCardContent(
                icon: "pencil.and.list.clipboard",
                label: "Annotate",
                sublabel: nil,
                tint: .blue,
                filled: false
            )
            .hoverEffect(.lift)
        }
        .buttonStyle(PressableCardStyle())
    }

    @ViewBuilder
    private var practiceCard: some View {
        let enabled = (parseResult?.dialogueTurns.isEmpty == false)
        Button {
            ReaderSidebarHaptic.fire(.light)
            isShowingPractice = true
        } label: {
            actionCardContent(
                icon: "mic.fill",
                label: "Practice",
                sublabel: enabled ? practiceSublabel : "Needs index",
                tint: .orange,
                filled: false,
                disabled: !enabled
            )
            .hoverEffect(.lift)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!enabled)
    }

    @ViewBuilder
    private var lyricsCard: some View {
        let enabled = (parseResult?.dialogueTurns.isEmpty == false)
        Button {
            ReaderSidebarHaptic.fire(.light)
            isShowingLyrics = true
        } label: {
            actionCardContent(
                icon: "text.alignleft",
                label: "Lyrics",
                sublabel: enabled ? nil : "Needs index",
                tint: .purple,
                filled: false,
                disabled: !enabled
            )
            .hoverEffect(.lift)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!enabled)
    }

    private var practiceSublabel: String? {
        guard let pr = parseResult else { return nil }
        return "\(pr.dialogueTurns.count) turns"
    }

    private func actionCardContent(
        icon: String,
        label: String,
        sublabel: String?,
        tint: Color,
        filled: Bool,
        disabled: Bool = false
    ) -> some View {
        let fg = disabled ? Color.secondary : tint
        let bg = disabled
            ? Color(.secondarySystemGroupedBackground)
            : (filled ? tint.opacity(0.18) : tint.opacity(0.10))

        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(fg)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(disabled ? .secondary : .primary)
                if let sublabel {
                    Text(sublabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bg)
        )
        .opacity(disabled ? 0.7 : 1.0)
    }

    // MARK: - Coverage

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Analysis")

            NavigationLink {
                CoverageView(document: document)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .frame(width: 36, height: 36)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coverage")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Logline, synopsis, recommendation")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .hoverEffect(.lift)
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    // MARK: - Bookmarks

    private var bookmarksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Bookmarks") {
                Text("\(bookmarks.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(bookmarks) { bookmark in
                    bookmarkRow(bookmark)
                }
            }
        }
    }

    private func bookmarkRow(_ bookmark: ScriptBookmark) -> some View {
        NavigationLink {
            ReaderSplitView(document: document, initialJumpToPage: bookmark.pageIndex)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.label ?? "Page \(bookmark.pageIndex + 1)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if bookmark.label != nil {
                        Text("Page \(bookmark.pageIndex + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .hoverEffect(.lift)
        }
        .buttonStyle(PressableCardStyle())
        .contextMenu {
            Button(role: .destructive) {
                ReaderSidebarHaptic.fire(.rigid)
                context.delete(bookmark)
                try? context.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
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

    private func statPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var remainingMinutes: Int {
        let progress = session?.progress ?? 0
        return max(Int(Double(document.estimatedMinutes) * (1 - progress)), 0)
    }

    private var indexStatusTitle: String {
        if isParsing {
            return "Indexing script"
        }
        if parseError != nil {
            return "Index unavailable"
        }
        if indexedAt != nil {
            return "Index ready"
        }
        return "Build practice index"
    }

    private var indexStatusMessage: String {
        if isParsing {
            return "Detecting scenes, characters, and dialogue turns."
        }
        if let parseError {
            return parseError
        }
        if let at = indexedAt {
            return "Updated \(at.formatted(.relative(presentation: .named)))."
        }
        return "Needed for Practice, Lyrics Mode, and faster navigation."
    }

    private var indexStatusIconName: String {
        if isParsing {
            return "gearshape"
        }
        if parseError != nil {
            return "exclamationmark.triangle.fill"
        }
        return indexedAt != nil ? "checkmark.circle.fill" : "wand.and.stars"
    }

    private var indexStatusColor: Color {
        if isParsing {
            return .orange
        }
        if parseError != nil {
            return .red
        }
        return indexedAt != nil ? .green : .secondary
    }
}
