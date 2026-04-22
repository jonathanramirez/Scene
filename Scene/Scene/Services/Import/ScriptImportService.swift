import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class ScriptImportService {

    func importPDF(from url: URL, into context: ModelContext) throws -> ScriptDocument {
        let localURL: URL

        do {
            localURL = try withSecurityScopedAccess(to: url) {
                try copyToDocumentsWithUniqueName(from: url)
            }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.generic("Import failed: \(error.localizedDescription)")
        }

        let pageCount = (try? PDFTextExtractor.pageCount(url: localURL)) ?? 0

        let doc = ScriptDocument(
            title: localURL.deletingPathExtension().lastPathComponent,
            originalFileName: localURL.lastPathComponent,
            fileURL: localURL,
            bookmarkData: nil,
            pageCount: pageCount
        )

        context.insert(doc)
        try context.save()
        return doc
    }

    // MARK: - Private

    private func withSecurityScopedAccess<T>(to url: URL, _ work: () throws -> T) throws -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        guard didStart else {
            throw AppError.fileAccessDenied
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        return try work()
    }

    private func copyToDocumentsWithUniqueName(from sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let targetDir = docs.appendingPathComponent("Scripts", isDirectory: true)

        if !fm.fileExists(atPath: targetDir.path) {
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        let fileName = uniqueFileName(for: sourceURL.lastPathComponent, in: targetDir)
        let targetURL = targetDir.appendingPathComponent(fileName)

        do {
            try fm.copyItem(at: sourceURL, to: targetURL)
            return targetURL
        } catch {
            throw AppError.generic("Could not copy the selected PDF into Scene.")
        }
    }

    private func uniqueFileName(for originalName: String, in directory: URL) -> String {
        let fm = FileManager.default

        let ext = (originalName as NSString).pathExtension
        let base = (originalName as NSString).deletingPathExtension

        var candidate = originalName
        var counter = 2

        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            if ext.isEmpty {
                candidate = "\(base) \(counter)"
            } else {
                candidate = "\(base) \(counter).\(ext)"
            }
            counter += 1
        }

        return candidate
    }
}
