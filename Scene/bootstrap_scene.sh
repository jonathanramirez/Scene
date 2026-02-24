#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Scene"
ROOT_DIR="${APP_NAME}"

mkdir -p "${ROOT_DIR}"/{App,Core/{Extensions},Data/{Persistence,Models},Services/{Import,PDF,Parsing},Features/{Library,Reader,Notes,Glossary,Coverage,Settings},Resources}

# --- App ---
cat > "${ROOT_DIR}/App/${APP_NAME}App.swift" <<EOF
import SwiftUI
import SwiftData

@main
struct ${APP_NAME}App: App {
    var body: some Scene {
        WindowGroup {
            AppRouter()
        }
        .modelContainer(ModelContainerFactory.make())
    }
}
EOF

cat > "${ROOT_DIR}/App/AppRouter.swift" <<'EOF'
import SwiftUI

struct AppRouter: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

            NotesView()
                .tabItem { Label("Notes", systemImage: "note.text") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
EOF

# --- Core ---
cat > "${ROOT_DIR}/Core/Logging.swift" <<'EOF'
import Foundation
import OSLog

enum Log {
    static let app = Logger(subsystem: "com.yourcompany.scene", category: "app")
    static let pdf = Logger(subsystem: "com.yourcompany.scene", category: "pdf")
    static let importFlow = Logger(subsystem: "com.yourcompany.scene", category: "import")
    static let parse = Logger(subsystem: "com.yourcompany.scene", category: "parse")
}
EOF

cat > "${ROOT_DIR}/Core/Errors.swift" <<'EOF'
import Foundation

enum AppError: LocalizedError {
    case generic(String)
    case importFailed
    case securityScopedAccessDenied
    case pdfOpenFailed
    case noFileURL

    var errorDescription: String? {
        switch self {
        case .generic(let msg): return msg
        case .importFailed: return "Import failed."
        case .securityScopedAccessDenied: return "Security-scoped access denied."
        case .pdfOpenFailed: return "Could not open PDF."
        case .noFileURL: return "No file URL on document."
        }
    }
}
EOF

cat > "${ROOT_DIR}/Core/Extensions/URL+SecurityScoped.swift" <<'EOF'
import Foundation

extension URL {
    func withSecurityScopedAccess<T>(_ work: () throws -> T) throws -> T {
        let ok = startAccessingSecurityScopedResource()
        defer { if ok { stopAccessingSecurityScopedResource() } }
        guard ok else { throw AppError.securityScopedAccessDenied }
        return try work()
    }
}
EOF

cat > "${ROOT_DIR}/Core/Extensions/String+Regex.swift" <<'EOF'
import Foundation

extension String {
    func matches(_ pattern: String) -> Bool {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(startIndex..<endIndex, in: self)
        return r.firstMatch(in: self, options: [], range: range) != nil
    }
}
EOF

# --- Persistence ---
cat > "${ROOT_DIR}/Data/Persistence/ModelContainerFactory.swift" <<'EOF'
import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make() -> ModelContainer {
        let schema = Schema([
            ScriptDocument.self,
            ScriptNote.self,
            ScriptBookmark.self,
            ScriptTag.self,
            ScriptReadingSession.self
        ])

        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
EOF

# --- Models ---
cat > "${ROOT_DIR}/Data/Models/ScriptDocument.swift" <<'EOF'
import Foundation
import SwiftData

@Model
final class ScriptDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var originalFileName: String
    var fileURL: URL?
    var createdAt: Date
    var lastOpenedAt: Date?

    // Keep security-scoped bookmark for Files imports
    var bookmarkData: Data?

    // Metadata
    var pageCount: Int
    var estimatedMinutes: Int

    init(title: String, originalFileName: String, fileURL: URL?, bookmarkData: Data?, pageCount: Int) {
        self.id = UUID()
        self.title = title
        self.originalFileName = originalFileName
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.createdAt = Date()
        self.lastOpenedAt = nil
        self.pageCount = pageCount
        self.estimatedMinutes = pageCount // 1 page ≈ 1 minute
    }
}
EOF

cat > "${ROOT_DIR}/Data/Models/ScriptReadingSession.swift" <<'EOF'
import Foundation
import SwiftData

enum ReadingMode: String, Codable {
    case firstRead
    case secondRead
}

@Model
final class ScriptReadingSession {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var modeRaw: String
    var lastPageIndex: Int
    var progress: Double
    var updatedAt: Date

    var mode: ReadingMode {
        get { ReadingMode(rawValue: modeRaw) ?? .firstRead }
        set { modeRaw = newValue.rawValue }
    }

    init(documentId: UUID, mode: ReadingMode) {
        self.id = UUID()
        self.documentId = documentId
        self.modeRaw = mode.rawValue
        self.lastPageIndex = 0
        self.progress = 0
        self.updatedAt = Date()
    }
}
EOF

cat > "${ROOT_DIR}/Data/Models/ScriptNote.swift" <<'EOF'
import Foundation
import SwiftData

enum NoteKind: String, Codable {
    case freeform
    case highlight
}

@Model
final class ScriptNote {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var createdAt: Date
    var updatedAt: Date

    var kindRaw: String
    var pageIndex: Int
    var text: String

    // Optional highlight rect stored as string: "x,y,w,h"
    var rectString: String?

    init(documentId: UUID, pageIndex: Int, text: String, kind: NoteKind = .freeform, rectString: String? = nil) {
        self.id = UUID()
        self.documentId = documentId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.kindRaw = kind.rawValue
        self.pageIndex = pageIndex
        self.text = text
        self.rectString = rectString
    }
}
EOF

cat > "${ROOT_DIR}/Data/Models/ScriptBookmark.swift" <<'EOF'
import Foundation
import SwiftData

@Model
final class ScriptBookmark {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var pageIndex: Int
    var label: String?
    var createdAt: Date

    init(documentId: UUID, pageIndex: Int, label: String? = nil) {
        self.id = UUID()
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.label = label
        self.createdAt = Date()
    }
}
EOF

cat > "${ROOT_DIR}/Data/Models/ScriptTag.swift" <<'EOF'
import Foundation
import SwiftData

@Model
final class ScriptTag {
    @Attribute(.unique) var id: UUID
    var name: String

    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}
EOF

cat > "${ROOT_DIR}/Data/Models/ScriptParseResult.swift" <<'EOF'
import Foundation

struct ScriptParseResult: Sendable, Codable {
    var scenes: [ScriptScene]
    var characters: [ScriptCharacter]
}
EOF

cat > "${ROOT_DIR}/Data/Models/ScriptScene.swift" <<'EOF'
import Foundation

struct ScriptScene: Identifiable, Sendable, Codable, Hashable {
    var id: UUID = UUID()
    var index: Int
    var heading: String
    var startPage: Int
    var endPage: Int?
}
EOF

cat > "${ROOT_DIR}/Data/Models/ScriptCharacter.swift" <<'EOF'
import Foundation

struct ScriptCharacter: Identifiable, Sendable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var firstPage: Int?
}
EOF

# --- Services: PDF ---
cat > "${ROOT_DIR}/Services/PDF/PDFTextExtractor.swift" <<'EOF'
import Foundation
import PDFKit

enum PDFTextExtractor {
    static func open(url: URL) throws -> PDFDocument {
        if let doc = PDFDocument(url: url) { return doc }
        throw AppError.pdfOpenFailed
    }

    static func pageCount(url: URL) throws -> Int {
        let doc = try open(url: url)
        return doc.pageCount
    }

    static func textByPage(url: URL, maxPages: Int = 400) throws -> [(pageIndex: Int, text: String)] {
        let doc = try open(url: url)
        let count = min(doc.pageCount, maxPages)

        return (0..<count).map { i in
            let page = doc.page(at: i)
            return (i, page?.string ?? "")
        }
    }
}
EOF

# --- Services: Parsing ---
cat > "${ROOT_DIR}/Services/Parsing/ScriptFormatHeuristics.swift" <<'EOF'
import Foundation

enum ScriptFormatHeuristics {
    /// Scene headings in US screenplays commonly start with INT./EXT./INT-EXT/I/E.
    static func isSceneHeading(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 5 else { return false }
        let u = s.uppercased()

        // Conservative checks
        if u.hasPrefix("INT.") || u.hasPrefix("EXT.") { return true }
        if u.hasPrefix("INT/EXT.") || u.hasPrefix("INT.-EXT.") || u.hasPrefix("INT-EXT.") { return true }
        if u.hasPrefix("I/E.") { return true }

        return false
    }

    /// Character cues: usually ALL CAPS, not too long, not a transition.
    static func looksLikeCharacterCue(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 2 && s.count <= 30 else { return false }

        // Must be mostly uppercase letters/spaces/'./()- and no colon at end
        let u = s.uppercased()
        guard s == u else { return false }

        // Exclude transitions
        if u.contains("CUT TO") || u.contains("FADE") || u.contains("DISSOLVE") { return false }

        // Exclude scene headings
        if isSceneHeading(s) { return false }

        // Exclude common non-character cues
        if u == "CONTINUED" { return false }

        return true
    }
}
EOF

cat > "${ROOT_DIR}/Services/Parsing/PDFOutlineBuilder.swift" <<'EOF'
import Foundation

enum PDFOutlineBuilder {
    static func buildScenes(from pages: [(pageIndex: Int, text: String)]) -> [ScriptScene] {
        var scenes: [ScriptScene] = []
        var idx = 0

        for (pageIndex, text) in pages {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for line in lines {
                if ScriptFormatHeuristics.isSceneHeading(line) {
                    idx += 1
                    scenes.append(.init(index: idx,
                                        heading: line.trimmingCharacters(in: .whitespacesAndNewlines),
                                        startPage: pageIndex,
                                        endPage: nil))
                }
            }
        }

        // Fill endPage
        if !scenes.isEmpty {
            for i in scenes.indices {
                let nextStart = (i + 1 < scenes.count) ? scenes[i + 1].startPage : nil
                scenes[i].endPage = nextStart.map { max($0 - 1, scenes[i].startPage) }
            }
        }

        return scenes
    }
}
EOF

cat > "${ROOT_DIR}/Services/Parsing/ScriptParser.swift" <<'EOF'
import Foundation

actor ScriptParser {
    func parse(url: URL) async throws -> ScriptParseResult {
        let pages = try PDFTextExtractor.textByPage(url: url)
        let scenes = PDFOutlineBuilder.buildScenes(from: pages)

        var characters: [String: ScriptCharacter] = [:]
        for (pageIndex, text) in pages {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for line in lines {
                if ScriptFormatHeuristics.looksLikeCharacterCue(line) {
                    let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if characters[name] == nil {
                        characters[name] = ScriptCharacter(name: name, firstPage: pageIndex)
                    }
                }
            }
        }

        let sortedChars = Array(characters.values).sorted { $0.name < $1.name }
        return ScriptParseResult(scenes: scenes, characters: sortedChars)
    }
}
EOF

# --- Services: Import ---
cat > "${ROOT_DIR}/Services/Import/ScriptImportService.swift" <<'EOF'
import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class ScriptImportService {
    func importPDF(from url: URL, into context: ModelContext) throws -> ScriptDocument {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let pageCount = (try? PDFTextExtractor.pageCount(url: url)) ?? 0

        let doc = ScriptDocument(
            title: url.deletingPathExtension().lastPathComponent,
            originalFileName: url.lastPathComponent,
            fileURL: url,
            bookmarkData: bookmark,
            pageCount: pageCount
        )

        context.insert(doc)
        try context.save()
        return doc
    }
}
EOF

# --- Features: Library ---
cat > "${ROOT_DIR}/Features/Library/LibraryView.swift" <<'EOF'
import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScriptDocument.createdAt, order: .reverse) private var docs: [ScriptDocument]
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(docs) { doc in
                    NavigationLink {
                        ReaderSplitView(document: doc)
                    } label: {
                        ScriptRowView(document: doc)
                    }
                }
            }
            .navigationTitle("Scene")
            .toolbar { ImportButton(isPresented: $isImporting) }
        }
    }
}
EOF

cat > "${ROOT_DIR}/Features/Library/ScriptRowView.swift" <<'EOF'
import SwiftUI

struct ScriptRowView: View {
    let document: ScriptDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title).font(.headline)
            Text("\(document.pageCount) pages • ~\(document.estimatedMinutes) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
EOF

cat > "${ROOT_DIR}/Features/Library/ImportButton.swift" <<'EOF'
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportButton: ToolbarContent {
    @Environment(\.modelContext) private var context
    @Binding var isPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresented = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let service = ScriptImportService()
                    _ = try service.importPDF(from: url, into: context)
                } catch {
                    Log.importFlow.error("Import failed: \(String(describing: error))")
                }
            }
        }
    }
}
EOF

# --- Features: Reader (SplitView + example parsing) ---
cat > "${ROOT_DIR}/Features/Reader/ReaderSplitView.swift" <<'EOF'
import SwiftUI

struct ReaderSplitView: View {
    let document: ScriptDocument
    @StateObject private var vm = ReaderSplitViewModel()

    var body: some View {
        NavigationSplitView {
            List {
                Section("Scenes") {
                    ForEach(vm.parseResult?.scenes ?? []) { scene in
                        Button {
                            vm.jumpToPage = scene.startPage
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
                        .buttonStyle(.plain)
                    }
                }

                Section("Characters") {
                    ForEach(vm.parseResult?.characters ?? []) { c in
                        HStack {
                            Text(c.name)
                            Spacer()
                            if let p = c.firstPage {
                                Text("p\(p + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(document.title)
        } detail: {
            ReaderView(document: document, jumpToPage: $vm.jumpToPage)
                .navigationTitle(document.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if vm.isParsing {
                            ProgressView()
                        } else {
                            Button("Rebuild Index") { Task { await vm.buildIndex(for: document) } }
                        }
                    }
                }
        }
        .task { await vm.buildIndex(for: document) }
    }
}
EOF

cat > "${ROOT_DIR}/Features/Reader/ReaderSplitViewModel.swift" <<'EOF'
import Foundation

@MainActor
final class ReaderSplitViewModel: ObservableObject {
    @Published var parseResult: ScriptParseResult?
    @Published var isParsing: Bool = false

    // When set, ReaderView will jump there
    @Published var jumpToPage: Int? = nil

    private let parser = ScriptParser()

    func buildIndex(for doc: ScriptDocument) async {
        guard let url = doc.fileURL else { return }
        isParsing = true
        defer { isParsing = false }

        do {
            let resolved = try resolveBookmarkIfNeeded(url: url, bookmark: doc.bookmarkData)
            let res = try await parser.parse(url: resolved)
            self.parseResult = res
        } catch {
            Log.parse.error("Parse failed: \(String(describing: error))")
            self.parseResult = nil
        }
    }

    private func resolveBookmarkIfNeeded(url: URL, bookmark: Data?) throws -> URL {
        guard let bookmark else { return url }
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        return resolved
    }
}
EOF

cat > "${ROOT_DIR}/Features/Reader/ReaderView.swift" <<'EOF'
import SwiftUI

struct ReaderView: View {
    let document: ScriptDocument
    @Binding var jumpToPage: Int?

    var body: some View {
        PDFKitRepresentedView(document: document, jumpToPage: $jumpToPage)
            .ignoresSafeArea(edges: .bottom)
    }
}
EOF

cat > "${ROOT_DIR}/Features/Reader/PDFKitRepresentedView.swift" <<'EOF'
import SwiftUI
import PDFKit

struct PDFKitRepresentedView: UIViewRepresentable {
    let document: ScriptDocument
    @Binding var jumpToPage: Int?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(true, withViewOptions: nil)
        view.backgroundColor = .systemBackground
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let url = document.fileURL else { return }

        do {
            let resolvedURL = try resolveBookmarkIfNeeded(url: url, bookmark: document.bookmarkData)
            if uiView.document == nil {
                uiView.document = PDFDocument(url: resolvedURL)
            }
            if let target = jumpToPage,
               let page = uiView.document?.page(at: target) {
                uiView.go(to: page)
                DispatchQueue.main.async { self.jumpToPage = nil }
            }
        } catch {
            Log.pdf.error("PDF load error: \(String(describing: error))")
        }
    }

    private func resolveBookmarkIfNeeded(url: URL, bookmark: Data?) throws -> URL {
        guard let bookmark else { return url }
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        return resolved
    }
}
EOF

# --- Features: Notes ---
cat > "${ROOT_DIR}/Features/Notes/NotesView.swift" <<'EOF'
import SwiftUI
import SwiftData

struct NotesView: View {
    @Query(sort: \ScriptNote.updatedAt, order: .reverse) private var notes: [ScriptNote]

    var body: some View {
        NavigationStack {
            List {
                ForEach(notes) { n in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.text).lineLimit(2)
                        Text("Page \(n.pageIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Notes")
        }
    }
}
EOF

# --- Features: Glossary ---
cat > "${ROOT_DIR}/Features/Glossary/GlossaryStore.swift" <<'EOF'
import Foundation

struct GlossaryTerm: Identifiable, Codable {
    var id: String { key }
    let key: String
    let title: String
    let description: String
}

@MainActor
final class GlossaryStore: ObservableObject {
    @Published private(set) var terms: [GlossaryTerm] = []

    func load() {
        guard let url = Bundle.main.url(forResource: "Glossary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([GlossaryTerm].self, from: data) else {
            terms = []
            return
        }
        terms = decoded.sorted { $0.title < $1.title }
    }
}
EOF

cat > "${ROOT_DIR}/Features/Glossary/GlossaryView.swift" <<'EOF'
import SwiftUI

struct GlossaryView: View {
    @StateObject private var store = GlossaryStore()
    @State private var query = ""

    private var filtered: [GlossaryTerm] {
        guard !query.isEmpty else { return store.terms }
        return store.terms.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.key.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(filtered) { t in
            VStack(alignment: .leading, spacing: 6) {
                Text(t.title).font(.headline)
                Text(t.description).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Glossary")
        .searchable(text: $query)
        .onAppear { store.load() }
    }
}
EOF

# --- Features: Coverage ---
cat > "${ROOT_DIR}/Features/Coverage/CoverageView.swift" <<'EOF'
import SwiftUI

struct CoverageView: View {
    @State private var logline = ""
    @State private var synopsis = ""
    @State private var comments = ""
    @State private var recommendation = ""

    var body: some View {
        Form {
            Section("Logline") { TextEditor(text: $logline).frame(minHeight: 80) }
            Section("Synopsis") { TextEditor(text: $synopsis).frame(minHeight: 120) }
            Section("Comments") { TextEditor(text: $comments).frame(minHeight: 120) }
            Section("Recommendation") { TextField("Pass / Consider / Recommend", text: $recommendation) }
        }
        .navigationTitle("Coverage")
    }
}
EOF

# --- Features: Settings ---
cat > "${ROOT_DIR}/Features/Settings/SettingsView.swift" <<'EOF'
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Reader") {
                    Toggle("Night Mode", isOn: .constant(false))
                    Toggle("First Read hints", isOn: .constant(true))
                }
                Section("About") {
                    LabeledContent("App", value: "Scene")
                    LabeledContent("Version", value: "0.1")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
EOF

# --- Resources ---
cat > "${ROOT_DIR}/Resources/Glossary.json" <<'EOF'
[
  { "key": "VO", "title": "V.O. (Voice Over)", "description": "Dialogue spoken over the scene, not coming from a visible character in the moment." },
  { "key": "OS", "title": "O.S. (Off Screen)", "description": "Dialogue spoken by a character who is present in the scene but not visible in the shot." },
  { "key": "PRELAP", "title": "PRE-LAP", "description": "Audio from the next scene begins before the visual cut to that scene." },
  { "key": "FADEIN", "title": "FADE IN", "description": "Transition where the picture appears gradually from black." },
  { "key": "FADEOUT", "title": "FADE OUT", "description": "Transition where the picture gradually disappears to black." },
  { "key": "CUTTO", "title": "CUT TO", "description": "Direct cut transition to the next shot/scene." }
]
EOF

cat > "${ROOT_DIR}/README.md" <<'EOF'
# Scene (iOS/iPadOS)

MVP:
- Import screenplay PDFs from Files
- Read with PDFKit
- Build a best-effort Scene Index (INT./EXT.)
- Extract character cues (heuristic)
- Glossary for common screenplay terms

Xcode steps:
1) Create a new iOS App project named "Scene" (SwiftUI + SwiftData)
2) Drag the Scene/ folder into the project (Create groups)
3) Ensure Resources/Glossary.json is included in Copy Bundle Resources
EOF

echo "✅ Created ${ROOT_DIR}/ structure with Swift stubs + ReaderSplitView example."
echo "Next steps:"
echo "1) Create an Xcode project named ${APP_NAME} (SwiftUI + SwiftData)"
echo "2) Drag the ${ROOT_DIR}/ folder into the project"
echo "3) Add Resources/Glossary.json to Copy Bundle Resources"
echo "4) Run → import a screenplay PDF → open → left sidebar shows Scenes/Characters"
