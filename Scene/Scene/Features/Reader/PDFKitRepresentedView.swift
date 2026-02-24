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
