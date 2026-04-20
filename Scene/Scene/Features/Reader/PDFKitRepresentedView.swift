import SwiftUI
import PDFKit
import PencilKit
import SwiftData
internal import os

struct PDFKitRepresentedView: UIViewRepresentable {
    @Environment(\.modelContext) private var modelContext
    let document: ScriptDocument
    @Binding var jumpToPage: Int?
    let isAnnotating: Bool
    let isPencilOnly: Bool

    func makeUIView(context: Context) -> ReaderContainerView {
        let view = ReaderContainerView()
        context.coordinator.configure(containerView: view, document: document, modelContext: modelContext)
        return view
    }

    func updateUIView(_ uiView: ReaderContainerView, context: Context) {
        context.coordinator.configure(containerView: uiView, document: document, modelContext: modelContext)

        do {
            let resolvedURL = try resolveDocumentURL(for: document)
            let loadedDocument = try loadDocument(from: resolvedURL, bookmark: document.bookmarkData)
            if uiView.pdfView.document == nil || uiView.pdfView.document?.pageCount != loadedDocument.pageCount {
                uiView.pdfView.document = loadedDocument
            }

            if let target = jumpToPage,
               let page = uiView.pdfView.document?.page(at: target) {
                context.coordinator.persistCurrentCanvasIfNeeded()
                uiView.pdfView.go(to: page)
                context.coordinator.loadDrawing(for: target)
                DispatchQueue.main.async {
                    self.jumpToPage = nil
                }
            }

            context.coordinator.setPencilOnly(isPencilOnly)
            context.coordinator.setAnnotationMode(isAnnotating)
        } catch {
            Log.pdf.error("PDF load error: \(String(describing: error))")
        }
    }

    static func dismantleUIView(_ uiView: ReaderContainerView, coordinator: Coordinator) {
        coordinator.persistCurrentCanvasIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func resolveDocumentURL(for document: ScriptDocument) throws -> URL {
        guard let url = document.fileURL else {
            throw AppError.pdfOpenFailed
        }
        return try resolveBookmarkIfNeeded(url: url, bookmark: document.bookmarkData)
    }

    private func resolveBookmarkIfNeeded(url: URL, bookmark: Data?) throws -> URL {
        guard let bookmark else { return url }
        var stale = false
        #if os(macOS)
        return try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #else
        return try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #endif
    }

    private func loadDocument(from url: URL, bookmark: Data?) throws -> PDFDocument {
        let hasSecurityScope = bookmark != nil ? url.startAccessingSecurityScopedResource() : false
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let document = PDFDocument(data: data) else {
            throw AppError.pdfOpenFailed
        }
        return document
    }
}

final class ReaderContainerView: UIView {
    let pdfView = PDFView()
    let canvasView = PKCanvasView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .systemBackground

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(false, withViewOptions: nil)
        pdfView.backgroundColor = .systemBackground

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.isScrollEnabled = false

        addSubview(pdfView)
        addSubview(canvasView)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

extension PDFKitRepresentedView {
    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private weak var containerView: ReaderContainerView?
        private var document: ScriptDocument?
        private var modelContext: ModelContext?
        private var loadedPageIndex = 0

        func configure(containerView: ReaderContainerView, document: ScriptDocument, modelContext: ModelContext) {
            self.containerView = containerView
            self.document = document
            self.modelContext = modelContext
            containerView.canvasView.delegate = self
        }

        func setAnnotationMode(_ isAnnotating: Bool) {
            guard let containerView else { return }
            containerView.canvasView.isHidden = !isAnnotating
            containerView.canvasView.isUserInteractionEnabled = isAnnotating
            containerView.pdfView.isUserInteractionEnabled = !isAnnotating

            if isAnnotating {
                loadDrawing(for: currentPageIndex())
                if let window = containerView.window {
                    let toolPicker = PKToolPicker.shared(for: window)
                    toolPicker?.addObserver(containerView.canvasView)
                    toolPicker?.setVisible(true, forFirstResponder: containerView.canvasView)
                    containerView.canvasView.becomeFirstResponder()
                }
            } else if let window = containerView.window {
                persistCurrentCanvasIfNeeded()
                let toolPicker = PKToolPicker.shared(for: window)
                toolPicker?.setVisible(false, forFirstResponder: containerView.canvasView)
                toolPicker?.removeObserver(containerView.canvasView)
                containerView.canvasView.resignFirstResponder()
            }
        }

        func setPencilOnly(_ isPencilOnly: Bool) {
            containerView?.canvasView.drawingPolicy = isPencilOnly ? .pencilOnly : .anyInput
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            persistDrawing(canvasView.drawing, for: currentPageIndex())
        }

        func loadDrawing(for pageIndex: Int) {
            guard let containerView else { return }
            loadedPageIndex = pageIndex

            if let drawing = storedDrawing(for: pageIndex) {
                containerView.canvasView.drawing = drawing
            } else {
                containerView.canvasView.drawing = PKDrawing()
            }
        }

        func persistCurrentCanvasIfNeeded() {
            guard let drawing = containerView?.canvasView.drawing else { return }
            persistDrawing(drawing, for: loadedPageIndex)
        }

        private func currentPageIndex() -> Int {
            guard
                let pdfView = containerView?.pdfView,
                let page = pdfView.currentPage
            else { return loadedPageIndex }

            return pdfView.document?.index(for: page) ?? loadedPageIndex
        }

        private func persistDrawing(_ drawing: PKDrawing, for pageIndex: Int) {
            guard
                let document,
                let modelContext
            else { return }

            let documentId = document.id
            let targetPageIndex = pageIndex
            var descriptor = FetchDescriptor<ScriptDrawing>(
                predicate: #Predicate<ScriptDrawing> {
                    $0.documentId == documentId && $0.pageIndex == targetPageIndex
                }
            )
            descriptor.fetchLimit = 1

            let drawingRecord = try? modelContext.fetch(descriptor).first

            if drawing.strokes.isEmpty {
                if let drawingRecord {
                    modelContext.delete(drawingRecord)
                }
            } else {
                let data = drawing.dataRepresentation()
                if let drawingRecord {
                    drawingRecord.drawingData = data
                    drawingRecord.updatedAt = Date()
                } else {
                    modelContext.insert(ScriptDrawing(documentId: documentId, pageIndex: targetPageIndex, drawingData: data))
                }
            }

            try? modelContext.save()
        }

        private func storedDrawing(for pageIndex: Int) -> PKDrawing? {
            guard
                let document,
                let modelContext
            else { return nil }

            let documentId = document.id
            let targetPageIndex = pageIndex
            var descriptor = FetchDescriptor<ScriptDrawing>(
                predicate: #Predicate<ScriptDrawing> {
                    $0.documentId == documentId && $0.pageIndex == targetPageIndex
                }
            )
            descriptor.fetchLimit = 1

            guard let drawingRecord = try? modelContext.fetch(descriptor).first else {
                return nil
            }

            return try? PKDrawing(data: drawingRecord.drawingData)
        }
    }
}
