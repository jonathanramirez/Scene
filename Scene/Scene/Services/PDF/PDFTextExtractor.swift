import Foundation
import PDFKit

enum PDFTextExtractor {
    nonisolated static func open(url: URL) throws -> PDFDocument {
        if let doc = PDFDocument(url: url) { return doc }
        throw AppError.pdfOpenFailed
    }

    nonisolated static func pageCount(url: URL) throws -> Int {
        let doc = try open(url: url)
        return doc.pageCount
    }

    nonisolated static func textByPage(url: URL, maxPages: Int = 400) throws -> [(pageIndex: Int, text: String)] {
        let doc = try open(url: url)
        let count = min(doc.pageCount, maxPages)

        return (0..<count).map { i in
            let page = doc.page(at: i)
            return (i, page?.string ?? "")
        }
    }
}
