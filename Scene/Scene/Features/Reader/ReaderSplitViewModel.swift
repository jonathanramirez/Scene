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
