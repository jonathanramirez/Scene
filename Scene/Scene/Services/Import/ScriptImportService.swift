import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class ScriptImportService {

    func importPDF(from url: URL, into context: ModelContext) throws -> ScriptDocument {
        let localURL = try copyToDocumentsIfNeeded(from: url)

        let pageCount = (try? PDFTextExtractor.pageCount(url: localURL)) ?? 0

        let doc = ScriptDocument(
            title: localURL.deletingPathExtension().lastPathComponent,
            originalFileName: url.lastPathComponent,
            fileURL: localURL,
            bookmarkData: nil, // ⬅️ NO bookmarks en iOS
            pageCount: pageCount
        )

        context.insert(doc)
        try context.save()
        return doc
    }

    // MARK: - Private

    private func copyToDocumentsIfNeeded(from sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let targetDir = docs.appendingPathComponent("Scripts", isDirectory: true)

        if !fm.fileExists(atPath: targetDir.path) {
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        let targetURL = targetDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Avoid overwriting existing files
        if fm.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        try fm.copyItem(at: sourceURL, to: targetURL)
        return targetURL
    }
}
