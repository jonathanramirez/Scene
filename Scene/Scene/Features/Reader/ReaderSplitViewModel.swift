import Combine
import Foundation
import SwiftData
internal import os

@MainActor
final class ReaderSplitViewModel: ObservableObject {
    @Published var parseResult: ScriptParseResult?
    @Published var isParsing: Bool = false
    @Published var indexedAt: Date? = nil

    // When set, ReaderView will jump there
    @Published var jumpToPage: Int? = nil

    private let parser = ScriptParser()

    func buildIndex(for doc: ScriptDocument, context: ModelContext, forceRebuild: Bool = false) async {
        // Check cache first
        if !forceRebuild, let cached = ParseCacheService.load(documentId: doc.id, context: context) {
            self.parseResult = cached.result
            self.indexedAt = cached.indexedAt
            return
        }

        guard let url = doc.resolvedFileURL else { return }
        isParsing = true
        defer { isParsing = false }

        do {
            let res = try await parser.parse(url: url)
            self.parseResult = res
            ParseCacheService.save(res, documentId: doc.id, context: context)
            self.indexedAt = Date()
        } catch {
            Log.parse.error("Parse failed: \(String(describing: error))")
            self.parseResult = nil
        }
    }
}
