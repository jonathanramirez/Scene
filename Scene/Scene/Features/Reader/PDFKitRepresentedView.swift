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
            let loadedDocument = try context.coordinator.pdfDocument(for: document)
            if uiView.pdfView.document !== loadedDocument {
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
        private var loadedDocumentID: UUID?
        private var loadedFileURL: URL?
        private var loadedFileModificationDate: Date?
        private var loadedPDFDocument: PDFDocument?
        private var configuredCanvasIdentifier: ObjectIdentifier?
        private let toolPicker = PKToolPicker()
        private var isToolPickerObserving = false

        func configure(containerView: ReaderContainerView, document: ScriptDocument, modelContext: ModelContext) {
            if self.document?.id != document.id {
                loadedPageIndex = 0
            }
            self.containerView = containerView
            self.document = document
            self.modelContext = modelContext
            containerView.canvasView.delegate = self
            configureCanvasDefaultsIfNeeded(containerView.canvasView)
        }

        func pdfDocument(for document: ScriptDocument) throws -> PDFDocument {
            guard let url = document.resolvedFileURL else { throw AppError.pdfOpenFailed }
            guard FileManager.default.fileExists(atPath: url.path) else { throw AppError.fileMissing }

            let modificationDate = fileModificationDate(for: url)
            if loadedDocumentID == document.id,
               loadedFileURL == url,
               loadedFileModificationDate == modificationDate,
               let loadedPDFDocument {
                return loadedPDFDocument
            }

            guard let pdfDocument = PDFDocument(url: url) else { throw AppError.pdfOpenFailed }
            loadedDocumentID = document.id
            loadedFileURL = url
            loadedFileModificationDate = modificationDate
            loadedPDFDocument = pdfDocument
            return pdfDocument
        }

        func setAnnotationMode(_ isAnnotating: Bool) {
            guard let containerView else { return }
            containerView.canvasView.isHidden = !isAnnotating
            containerView.canvasView.isUserInteractionEnabled = isAnnotating
            containerView.pdfView.isUserInteractionEnabled = !isAnnotating

            if isAnnotating {
                loadDrawing(for: currentPageIndex())
                showToolPicker(for: containerView.canvasView)
            } else {
                persistCurrentCanvasIfNeeded()
                hideToolPicker(for: containerView.canvasView)
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

        private func configureCanvasDefaultsIfNeeded(_ canvasView: PKCanvasView) {
            let identifier = ObjectIdentifier(canvasView)
            guard configuredCanvasIdentifier != identifier else { return }
            configuredCanvasIdentifier = identifier
            canvasView.tool = PKInkingTool(.pen, color: .systemBlue, width: 5)
        }

        private func showToolPicker(for canvasView: PKCanvasView) {
            if !isToolPickerObserving {
                toolPicker.addObserver(canvasView)
                isToolPickerObserving = true
            }
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }

        private func hideToolPicker(for canvasView: PKCanvasView) {
            toolPicker.setVisible(false, forFirstResponder: canvasView)
            if isToolPickerObserving {
                toolPicker.removeObserver(canvasView)
                isToolPickerObserving = false
            }
            canvasView.resignFirstResponder()
        }

        private func fileModificationDate(for url: URL) -> Date? {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return attributes?[.modificationDate] as? Date
        }
    }
}
