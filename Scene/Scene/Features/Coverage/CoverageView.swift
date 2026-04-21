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

    var body: some View {
        Form {
            // Auto-generate banner
            if logline.isEmpty && synopsis.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Generate a draft coverage from the indexed script data.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
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
                        .disabled(isGenerating || ParseCacheService.load(documentId: document.id, context: context) == nil)

                        if ParseCacheService.load(documentId: document.id, context: context) == nil {
                            Text("Index this script first to enable auto-generate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Recommendation") {
                Picker("Recommendation", selection: $recommendation) {
                    ForEach(ScriptCoverage.Recommendation.allCases) { rec in
                        Text(rec.rawValue).tag(rec)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: recommendation) { _, _ in isDirty = true }
            }

            Section("Logline") {
                TextEditor(text: $logline)
                    .frame(minHeight: 80)
                    .onChange(of: logline) { _, _ in isDirty = true }
            }

            Section("Synopsis") {
                TextEditor(text: $synopsis)
                    .frame(minHeight: 120)
                    .onChange(of: synopsis) { _, _ in isDirty = true }
            }

            Section("Comments") {
                TextEditor(text: $comments)
                    .frame(minHeight: 120)
                    .onChange(of: comments) { _, _ in isDirty = true }
            }

            Section {
                Button {
                    saveCoverage()
                } label: {
                    Label("Save Coverage", systemImage: "square.and.arrow.down")
                }
                .disabled(!isDirty)

                Button {
                    shareText = formatCoverageText()
                } label: {
                    Label("Share Coverage", systemImage: "square.and.arrow.up")
                }
                .disabled(logline.isEmpty && synopsis.isEmpty && comments.isEmpty)
            }
        }
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
