import SwiftUI
import Combine
import PDFKit
import PencilKit
import SwiftData
internal import os

private enum SceneAnnotationTool: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .pen: return .pen
        case .highlighter: return .marker
        case .eraser: return .pen
        }
    }

    var width: CGFloat {
        switch self {
        case .pen: return 5
        case .highlighter: return 18
        case .eraser: return 10
        }
    }
}

private enum SceneAnnotationColor: String, CaseIterable, Identifiable {
    case blue
    case red
    case green
    case black

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .red: return .red
        case .green: return .green
        case .black: return .black
        }
    }

    var uiColor: UIColor {
        switch self {
        case .blue: return .systemBlue
        case .red: return .systemRed
        case .green: return .systemGreen
        case .black: return .black
        }
    }
}

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    let document: ScriptDocument
    @Binding var jumpToPage: Int?
    @State private var isAnnotating = false
    @State private var isPencilOnly = false
    @State private var selectedTool: SceneAnnotationTool = .pen
    @State private var selectedColor: SceneAnnotationColor = .blue
    @State private var clearCurrentPageTrigger = 0
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    isAnnotating.toggle()
                } label: {
                    Label(isAnnotating ? "Stop Editing" : "Annotate", systemImage: isAnnotating ? "pencil.circle.fill" : "pencil.circle")
                }

                Button {
                    exportAnnotatedPDF()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }

                Spacer()

                Toggle("Pencil Only", isOn: $isPencilOnly)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            if isAnnotating {
                HStack {
                    Menu {
                        ForEach(SceneAnnotationTool.allCases) { tool in
                            Button {
                                selectedTool = tool
                            } label: {
                                Label(tool.title, systemImage: tool.systemImage)
                            }
                        }
                    } label: {
                        Label(selectedTool.title, systemImage: selectedTool.systemImage)
                    }

                    Menu {
                        ForEach(SceneAnnotationColor.allCases) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 14, height: 14)
                                    Text(color.title)
                                }
                            }
                        }
                    } label: {
                        Circle()
                            .fill(selectedColor.color)
                            .frame(width: 20, height: 20)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        clearCurrentPageTrigger += 1
                    } label: {
                        Label("Clear Page", systemImage: "trash")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }

            EmbeddedPDFKitRepresentedView(
                document: document,
                jumpToPage: $jumpToPage,
                isAnnotating: isAnnotating,
                isPencilOnly: isPencilOnly,
                selectedTool: selectedTool,
                selectedColor: selectedColor,
                clearCurrentPageTrigger: clearCurrentPageTrigger
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: exportSheetBinding) {
            if let exportURL {
                ActivityView(items: [exportURL])
            }
        }
    }

    private func exportAnnotatedPDF() {
        do {
            exportURL = try PDFExportService.exportAnnotatedPDF(for: document, from: modelContext)
        } catch {
            Log.pdf.error("Export failed: \(String(describing: error))")
        }
    }

    private var exportSheetBinding: Binding<Bool> {
        Binding(
            get: { exportURL != nil },
            set: { isPresented in
                if !isPresented {
                    exportURL = nil
                }
            }
        )
    }
}

private struct EmbeddedPDFKitRepresentedView: UIViewRepresentable {
    @Environment(\.modelContext) private var modelContext
    let document: ScriptDocument
    @Binding var jumpToPage: Int?
    let isAnnotating: Bool
    let isPencilOnly: Bool
    let selectedTool: SceneAnnotationTool
    let selectedColor: SceneAnnotationColor
    let clearCurrentPageTrigger: Int

    func makeUIView(context: Context) -> EmbeddedReaderContainerView {
        let view = EmbeddedReaderContainerView()
        context.coordinator.configure(containerView: view, document: document, modelContext: modelContext)
        return view
    }

    func updateUIView(_ uiView: EmbeddedReaderContainerView, context: Context) {
        context.coordinator.configure(containerView: uiView, document: document, modelContext: modelContext)

        do {
            guard let url = document.fileURL else { throw AppError.pdfOpenFailed }
            let data = try Data(contentsOf: url)
            guard let loadedDocument = PDFDocument(data: data) else { throw AppError.pdfOpenFailed }
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
            context.coordinator.setTool(selectedTool, color: selectedColor)
            context.coordinator.setAnnotationMode(isAnnotating)
            context.coordinator.handleClearTrigger(clearCurrentPageTrigger)
        } catch {
            Log.pdf.error("PDF load error: \(String(describing: error))")
        }
    }

    static func dismantleUIView(_ uiView: EmbeddedReaderContainerView, coordinator: Coordinator) {
        coordinator.persistCurrentCanvasIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, PDFPageOverlayViewProvider {
        private weak var containerView: EmbeddedReaderContainerView?
        private var document: ScriptDocument?
        private var modelContext: ModelContext?
        private var loadedPageIndex = 0
        private var pageChangedObserver: NSObjectProtocol?
        private var pageOverlayViews: [Int: UIImageView] = [:]
        private var selectedTool: SceneAnnotationTool = .pen
        private var selectedColor: SceneAnnotationColor = .blue
        private var lastClearTrigger = 0

        func configure(containerView: EmbeddedReaderContainerView, document: ScriptDocument, modelContext: ModelContext) {
            self.containerView = containerView
            self.document = document
            self.modelContext = modelContext
            containerView.canvasView.delegate = self
            containerView.canvasView.tool = currentPKTool()
            containerView.pdfView.pageOverlayViewProvider = self
            installPageObserverIfNeeded(for: containerView.pdfView)
        }

        func setAnnotationMode(_ isAnnotating: Bool) {
            guard let containerView else { return }
            containerView.canvasView.isHidden = !isAnnotating
            containerView.canvasView.isUserInteractionEnabled = isAnnotating
            containerView.pdfView.isUserInteractionEnabled = true

            if isAnnotating {
                containerView.pdfView.displayMode = .singlePage
                loadDrawing(for: currentPageIndex())
                refreshAllOverlays(hidden: true)
                if let window = containerView.window {
                    let toolPicker = PKToolPicker.shared(for: window)
                    toolPicker?.addObserver(containerView.canvasView)
                    toolPicker?.setVisible(true, forFirstResponder: containerView.canvasView)
                    containerView.canvasView.becomeFirstResponder()
                }
            } else if let window = containerView.window {
                persistCurrentCanvasIfNeeded()
                containerView.pdfView.displayMode = .singlePageContinuous
                containerView.pdfView.autoScales = true
                let toolPicker = PKToolPicker.shared(for: window)
                toolPicker?.setVisible(false, forFirstResponder: containerView.canvasView)
                toolPicker?.removeObserver(containerView.canvasView)
                containerView.canvasView.resignFirstResponder()
                refreshAllOverlays(hidden: false)
            }
        }

        func setPencilOnly(_ isPencilOnly: Bool) {
            containerView?.canvasView.drawingPolicy = isPencilOnly ? .pencilOnly : .anyInput
        }

        func setTool(_ tool: SceneAnnotationTool, color: SceneAnnotationColor) {
            selectedTool = tool
            selectedColor = color
            containerView?.canvasView.tool = currentPKTool()
        }

        func handleClearTrigger(_ trigger: Int) {
            guard trigger != lastClearTrigger else { return }
            lastClearTrigger = trigger
            clearDrawing(for: currentPageIndex())
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
            guard let document, let modelContext else { return }
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
            refreshOverlay(for: pageIndex, hidden: false)
        }

        private func clearDrawing(for pageIndex: Int) {
            if currentPageIndex() == pageIndex {
                containerView?.canvasView.drawing = PKDrawing()
            }
            persistDrawing(PKDrawing(), for: pageIndex)
        }

        private func storedDrawing(for pageIndex: Int) -> PKDrawing? {
            guard let document, let modelContext else { return nil }
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

        func pdfView(_ pdfView: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            let pageIndex = pdfView.document?.index(for: page) ?? 0
            let imageView = pageOverlayViews[pageIndex] ?? makeOverlayView(for: pageIndex, page: page)
            imageView.image = overlayImage(for: pageIndex, page: page)
            imageView.isHidden = !containerCanvasHiddenState()
            return imageView
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let pageIndex = pdfView.document?.index(for: page) else { return }
            pageOverlayViews[pageIndex]?.image = overlayImage(for: pageIndex, page: page)
        }

        private func makeOverlayView(for pageIndex: Int, page: PDFPage) -> UIImageView {
            let imageView = UIImageView()
            imageView.backgroundColor = .clear
            imageView.contentMode = .scaleToFill
            imageView.isUserInteractionEnabled = false
            imageView.image = overlayImage(for: pageIndex, page: page)
            pageOverlayViews[pageIndex] = imageView
            return imageView
        }

        private func overlayImage(for pageIndex: Int, page: PDFPage) -> UIImage? {
            guard let drawing = storedDrawing(for: pageIndex) else { return nil }
            return drawing.image(from: page.bounds(for: .mediaBox), scale: 1)
        }

        private func refreshOverlay(for pageIndex: Int, hidden: Bool) {
            guard
                let pdfView = containerView?.pdfView,
                let page = pdfView.document?.page(at: pageIndex)
            else { return }

            let imageView = pageOverlayViews[pageIndex] ?? makeOverlayView(for: pageIndex, page: page)
            imageView.image = overlayImage(for: pageIndex, page: page)
            imageView.isHidden = hidden
        }

        private func refreshAllOverlays(hidden: Bool) {
            guard let pdfView = containerView?.pdfView,
                  let document = pdfView.document
            else { return }

            for pageIndex in 0..<document.pageCount {
                refreshOverlay(for: pageIndex, hidden: hidden)
            }
        }

        private func containerCanvasHiddenState() -> Bool {
            containerView?.canvasView.isHidden ?? true
        }

        private func currentPKTool() -> PKTool {
            switch selectedTool {
            case .eraser:
                return PKEraserTool(.vector)
            case .pen, .highlighter:
                return PKInkingTool(selectedTool.inkType, color: selectedColor.uiColor, width: selectedTool.width)
            }
        }

        private func installPageObserverIfNeeded(for pdfView: PDFView) {
            guard pageChangedObserver == nil else { return }

            pageChangedObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] notification in
                guard
                    let self,
                    let pdfView = notification.object as? PDFView,
                    let page = pdfView.currentPage
                else { return }

                self.persistCurrentCanvasIfNeeded()
                let pageIndex = pdfView.document?.index(for: page) ?? self.loadedPageIndex
                self.loadDrawing(for: pageIndex)
            }
        }

        deinit {
            if let pageChangedObserver {
                NotificationCenter.default.removeObserver(pageChangedObserver)
            }
        }
    }
}

private final class EmbeddedReaderContainerView: UIView {
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
        pdfView.displayMode = .singlePageContinuous
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
