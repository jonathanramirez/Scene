import SwiftData
import SwiftUI

struct CoverageView: View {
    @Environment(\.modelContext) private var context

    let document: ScriptDocument

    @Query(sort: \ScriptCoverage.updatedAt, order: .reverse)
    private var allCoverages: [ScriptCoverage]

    private var coverage: ScriptCoverage? {
        allCoverages.first { $0.documentId == document.id }
    }

    @State private var logline = ""
    @State private var synopsis = ""
    @State private var comments = ""
    @State private var recommendation: ScriptCoverage.Recommendation = .consider
    @State private var isDirty = false
    @State private var shareText: String?
    @State private var isGenerating = false

    private var hasIndex: Bool {
        ParseCacheService.load(documentId: document.id, context: context) != nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if logline.isEmpty && synopsis.isEmpty {
                    generateDraftCard
                }
                recommendationCard
                loglineCard
                synopsisCard
                commentsCard
                actionsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Coverage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isDirty {
                    Button("Save") { saveCoverage() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { loadCoverage() }
        .onChange(of: coverage?.updatedAt) { _, _ in loadCoverage() }
        .sheet(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) {
            if let text = shareText {
                ShareSheet(items: [text])
            }
        }
    }

    // MARK: - Cards

    private var generateDraftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Draft")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 36, height: 36)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Generate a draft")
                            .font(.subheadline.weight(.semibold))
                        Text(hasIndex
                            ? "Auto-filled from the indexed script data."
                            : "Index this script first to enable auto-generate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                Button {
                    ReaderSidebarHaptic.fire(.light)
                    generateDraft()
                } label: {
                    if isGenerating {
                        Label("Generating…", systemImage: "wand.and.stars")
                    } else {
                        Label("Generate Draft", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .disabled(isGenerating || !hasIndex)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Recommendation")

            Picker("Recommendation", selection: $recommendation) {
                ForEach(ScriptCoverage.Recommendation.allCases) { rec in
                    Text(rec.rawValue).tag(rec)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: recommendation) { _, _ in isDirty = true }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var loglineCard: some View {
        editorCard(title: "Logline", text: $logline, minHeight: 90)
    }

    private var synopsisCard: some View {
        editorCard(title: "Synopsis", text: $synopsis, minHeight: 140)
    }

    private var commentsCard: some View {
        editorCard(title: "Comments", text: $comments, minHeight: 140)
    }

    private func editorCard(title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader(title)

            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .onChange(of: text.wrappedValue) { _, _ in isDirty = true }
        }
    }

    private var actionsCard: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
            spacing: 10
        ) {
            Button {
                ReaderSidebarHaptic.fire(.light)
                saveCoverage()
            } label: {
                actionContent(
                    icon: "square.and.arrow.down",
                    label: "Save",
                    tint: .orange,
                    disabled: !isDirty
                )
                .hoverEffect(.lift)
            }
            .buttonStyle(PressableCardStyle())
            .disabled(!isDirty)

            Button {
                ReaderSidebarHaptic.fire(.light)
                shareText = formatCoverageText()
            } label: {
                actionContent(
                    icon: "square.and.arrow.up",
                    label: "Share",
                    tint: .blue,
                    disabled: logline.isEmpty && synopsis.isEmpty && comments.isEmpty
                )
                .hoverEffect(.lift)
            }
            .buttonStyle(PressableCardStyle())
            .disabled(logline.isEmpty && synopsis.isEmpty && comments.isEmpty)
        }
    }

    private func actionContent(icon: String, label: String, tint: Color, disabled: Bool) -> some View {
        let fg = disabled ? Color.secondary : tint
        let bg = disabled
            ? Color(.secondarySystemGroupedBackground)
            : tint.opacity(0.10)

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(fg)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(disabled ? .secondary : .primary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bg)
        )
        .opacity(disabled ? 0.7 : 1.0)
    }

    // MARK: - Data

    private func loadCoverage() {
        guard let c = coverage else { return }
        logline = c.logline
        synopsis = c.synopsis
        comments = c.comments
        recommendation = c.recommendation
        isDirty = false
    }

    private func saveCoverage() {
        if let existing = coverage {
            existing.logline = logline
            existing.synopsis = synopsis
            existing.comments = comments
            existing.recommendation = recommendation
            existing.updatedAt = Date()
        } else {
            let c = ScriptCoverage(documentId: document.id)
            c.logline = logline
            c.synopsis = synopsis
            c.comments = comments
            c.recommendation = recommendation
            context.insert(c)
        }
        try? context.save()
        isDirty = false
    }

    private func generateDraft() {
        guard let cached = ParseCacheService.load(documentId: document.id, context: context) else { return }
        let result = cached.result
        isGenerating = true

        let topCharacters = result.dialogueTurns
            .reduce(into: [String: Int]()) { $0[$1.characterName, default: 0] += 1 }
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map(\.key)

        let charList = topCharacters.isEmpty ? "an ensemble cast"
            : topCharacters.dropLast().joined(separator: ", ")
              + (topCharacters.count > 1 ? " and \(topCharacters.last!)" : topCharacters.first!)

        let sceneCount  = result.scenes.count
        let turnCount   = result.dialogueTurns.count
        let pageCount   = document.pageCount

        // Logline
        if let firstScene = result.scenes.first {
            logline = "\(firstScene.heading.capitalized.trimmingCharacters(in: .whitespaces)) — "
                    + "A \(pageCount)-page screenplay featuring \(charList) "
                    + "across \(sceneCount) scene\(sceneCount == 1 ? "" : "s")."
        } else {
            logline = "A \(pageCount)-page screenplay featuring \(charList)."
        }

        // Synopsis — scene-by-scene outline
        let synopsisLines = result.scenes.map { scene in
            "Scene \(scene.index) — \(scene.heading) (p\(scene.startPage + 1))"
        }
        synopsis = synopsisLines.isEmpty
            ? "No scene headings detected."
            : synopsisLines.joined(separator: "\n")

        // Comments — structural stats
        let dominantChar = topCharacters.first ?? "N/A"
        let dominantCount = result.dialogueTurns.filter { $0.characterName == dominantChar }.count
        comments = """
            Pages: \(pageCount) (~\(document.estimatedMinutes) min)
            Scenes: \(sceneCount)
            Dialogue turns: \(turnCount)
            Dominant character: \(dominantChar) (\(dominantCount) turns)
            Total speaking roles: \(Set(result.dialogueTurns.map(\.characterName)).count)
            """

        isDirty = true
        isGenerating = false
    }

    private func formatCoverageText() -> String {
        """
        COVERAGE: \(document.title)
        Recommendation: \(recommendation.rawValue.uppercased())

        LOGLINE:
        \(logline)

        SYNOPSIS:
        \(synopsis)

        COMMENTS:
        \(comments)
        """
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
