import Foundation
import PDFKit
import PencilKit
import SwiftData
import UIKit

@MainActor
enum PDFExportService {
    static func exportAnnotatedPDF(for document: ScriptDocument, from context: ModelContext) throws -> URL {
        guard let sourceURL = document.resolvedFileURL else {
            throw AppError.noFileURL
        }

        guard let pdfDocument = PDFDocument(url: sourceURL) else {
            throw AppError.pdfOpenFailed
        }

        let drawings = try context.fetch(FetchDescriptor<ScriptDrawing>())
            .filter { $0.documentId == document.id }
        let drawingsByPage = Dictionary(uniqueKeysWithValues: drawings.map { ($0.pageIndex, $0) })

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(document.title)
            .appendingPathExtension("pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: exportURL) { context in
            for pageIndex in 0..<pdfDocument.pageCount {
                guard let page = pdfDocument.page(at: pageIndex) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                guard let cgContext = UIGraphicsGetCurrentContext() else { continue }

                cgContext.saveGState()
                page.draw(with: .mediaBox, to: cgContext)

                if let drawingModel = drawingsByPage[pageIndex],
                   let drawing = try? PKDrawing(data: drawingModel.drawingData) {
                    let image = drawing.image(from: bounds, scale: 1)
                    image.draw(in: bounds)
                }

                cgContext.restoreGState()
            }
        }

        return exportURL
    }
}
