import SwiftUI
import Combine
import PDFKit
import PencilKit
import SwiftData
internal import os


struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScriptNote.updatedAt, order: .reverse) private var allNotes: [ScriptNote]

    let document: ScriptDocument
    let dialogueTurns: [ScriptDialogueTurn]
    let dialogueHighlightSettings: PDFDialogueHighlightSettings
    @Binding var jumpToPage: Int?
    @Binding var searchHighlight: PDFSearchHighlight?
    @State private var isAnnotating = false
    @State private var isPencilOnly = false
    @State private var clearCurrentPageTrigger = 0
    @State private var exportURL: URL?
    @State private var exportErrorMessage: String?
    var onPageChanged: ((Int) -> Void)?
    var onDialogueTurnSelected: ((ScriptDialogueTurn) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            EmbeddedPDFKitRepresentedView(
                document: document,
                notes: notes,
                dialogueTurns: dialogueTurns,
                dialogueHighlightSettings: dialogueHighlightSettings,
                jumpToPage: $jumpToPage,
                searchHighlight: $searchHighlight,
                isAnnotating: isAnnotating,
                isPencilOnly: isPencilOnly,
                clearCurrentPageTrigger: clearCurrentPageTrigger,
                onPageChanged: onPageChanged,
                onDialogueTurnSelected: onDialogueTurnSelected
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .toolbar {
            // Single orange toggle — PKToolPicker floats natively when active
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAnnotating.toggle()
                } label: {
                    Image(systemName: isAnnotating ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                        .foregroundStyle(.orange)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportAnnotatedPDF()
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button {
                        isPencilOnly.toggle()
                    } label: {
                        Label(
                            isPencilOnly ? "Pencil Only: On" : "Pencil Only: Off",
                            systemImage: isPencilOnly ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle"
                        )
                    }

                    if isAnnotating {
                        Divider()
                        Button(role: .destructive) {
                            clearCurrentPageTrigger += 1
                        } label: {
                            Label("Clear Page", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: exportSheetBinding) {
            if let exportURL {
                ActivityView(items: [exportURL])
            }
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? AppError.exportFailed.localizedDescription)
        }
    }

    private var notes: [ScriptNote] {
        allNotes.filter { $0.documentId == document.id }
    }

    private func exportAnnotatedPDF() {
        do {
            exportURL = try PDFExportService.exportAnnotatedPDF(for: document, from: modelContext)
        } catch {
            Log.pdf.error("Export failed: \(String(describing: error))")
            exportErrorMessage = error.localizedDescription
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
    let notes: [ScriptNote]
    let dialogueTurns: [ScriptDialogueTurn]
    let dialogueHighlightSettings: PDFDialogueHighlightSettings
    @Binding var jumpToPage: Int?
    @Binding var searchHighlight: PDFSearchHighlight?
    let isAnnotating: Bool
    let isPencilOnly: Bool
    let clearCurrentPageTrigger: Int
    var onPageChanged: ((Int) -> Void)?
    var onDialogueTurnSelected: ((ScriptDialogueTurn) -> Void)?

    func makeUIView(context: Context) -> EmbeddedReaderContainerView {
        let view = EmbeddedReaderContainerView()
        context.coordinator.configure(containerView: view, document: document, modelContext: modelContext)
        return view
    }

    func updateUIView(_ uiView: EmbeddedReaderContainerView, context: Context) {
        context.coordinator.configure(containerView: uiView, document: document, modelContext: modelContext)

        do {
            let loadedDocument = try context.coordinator.pdfDocument(for: document)
            if uiView.pdfView.document !== loadedDocument {
                uiView.pdfView.document = loadedDocument
            }

            context.coordinator.setNotes(notes)
            context.coordinator.setDialogueHighlights(
                turns: dialogueTurns,
                settings: dialogueHighlightSettings
            )
            context.coordinator.onDialogueTurnSelected = onDialogueTurnSelected
            if let target = jumpToPage,
               let page = uiView.pdfView.document?.page(at: target) {
                context.coordinator.persistCurrentCanvasIfNeeded()
                uiView.pdfView.go(to: page)
                context.coordinator.loadDrawing(for: target)
                DispatchQueue.main.async {
                    self.jumpToPage = nil
                }
            }

            context.coordinator.applySearchHighlight(searchHighlight, in: uiView.pdfView)
            context.coordinator.setPencilOnly(isPencilOnly)
            context.coordinator.setAnnotationMode(isAnnotating)
            context.coordinator.handleClearTrigger(clearCurrentPageTrigger)
            context.coordinator.onPageChanged = onPageChanged
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
        private var loadedDocumentID: UUID?
        private var loadedFileURL: URL?
        private var loadedFileModificationDate: Date?
        private var loadedPDFDocument: PDFDocument?
        private var pageChangedObserver: NSObjectProtocol?
        private var pageOverlayViews: [Int: ReaderPageOverlayView] = [:]
        private var notesByPage: [Int: [ScriptNote]] = [:]
        private var dialogueTurnsByPage: [Int: [ScriptDialogueTurn]] = [:]
        private var dialogueCharacters: [String] = []
        private var dialogueHighlightSettings = PDFDialogueHighlightSettings()
        private var dialogueHighlightRectCache: [Int: [CGRect]] = [:]
        private var dialogueTurnsSignature = ""
        private var configuredCanvasIdentifier: ObjectIdentifier?
        private var lastClearTrigger = 0
        private var lastSearchHighlightID: PDFSearchHighlight.ID?
        private let toolPicker = PKToolPicker()
        private var isToolPickerObserving = false
        var onPageChanged: ((Int) -> Void)?
        var onDialogueTurnSelected: ((ScriptDialogueTurn) -> Void)?

        func configure(containerView: EmbeddedReaderContainerView, document: ScriptDocument, modelContext: ModelContext) {
            if self.document?.id != document.id {
                loadedPageIndex = 0
                pageOverlayViews.removeAll()
                notesByPage.removeAll()
                dialogueTurnsByPage.removeAll()
                dialogueHighlightRectCache.removeAll()
            }
            self.containerView = containerView
            self.document = document
            self.modelContext = modelContext
            containerView.canvasView.delegate = self
            configureCanvasDefaultsIfNeeded(containerView.canvasView)
            containerView.pdfView.pageOverlayViewProvider = self
            installPageObserverIfNeeded(for: containerView.pdfView)
        }

        func setNotes(_ notes: [ScriptNote]) {
            notesByPage = Dictionary(grouping: notes, by: \.pageIndex)
            refreshVisibleNoteMarkers()
        }

        func setDialogueHighlights(turns: [ScriptDialogueTurn], settings: PDFDialogueHighlightSettings) {
            let signature = turns.map { "\($0.sequenceIndex):\($0.pageIndex):\($0.characterName):\($0.dialogue.count)" }
                .joined(separator: "|")
            if signature != dialogueTurnsSignature {
                dialogueTurnsSignature = signature
                dialogueHighlightRectCache.removeAll()
            }

            dialogueHighlightSettings = settings
            dialogueCharacters = Array(Set(turns.map(\.characterName))).sorted()
            dialogueTurnsByPage = Dictionary(grouping: turns, by: \.pageIndex)
            refreshVisibleNoteMarkers()
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
            pageOverlayViews.removeAll()
            dialogueHighlightRectCache.removeAll()
            return pdfDocument
        }

        func setAnnotationMode(_ isAnnotating: Bool) {
            guard let containerView else { return }
            containerView.canvasView.isHidden = !isAnnotating
            containerView.canvasView.isUserInteractionEnabled = isAnnotating
	            containerView.pdfView.isUserInteractionEnabled = true

	            if isAnnotating {
	                loadDrawing(for: currentPageIndex())
	                refreshAllOverlays(hidden: true)
	                showToolPicker(for: containerView.canvasView)
	            } else {
	                persistCurrentCanvasIfNeeded()
	                containerView.pdfView.autoScales = true
	                hideToolPicker(for: containerView.canvasView)
	                refreshAllOverlays(hidden: false)
	            }
        }

        func setPencilOnly(_ isPencilOnly: Bool) {
            containerView?.canvasView.drawingPolicy = isPencilOnly ? .pencilOnly : .anyInput
        }

        func handleClearTrigger(_ trigger: Int) {
            guard trigger != lastClearTrigger else { return }
            lastClearTrigger = trigger
            clearDrawing(for: currentPageIndex())
        }

        func applySearchHighlight(_ highlight: PDFSearchHighlight?, in pdfView: PDFView) {
            guard let highlight else {
                if lastSearchHighlightID != nil {
                    pdfView.highlightedSelections = nil
                    pdfView.currentSelection = nil
                    lastSearchHighlightID = nil
                }
                return
            }
            guard lastSearchHighlightID != highlight.id else { return }
            lastSearchHighlightID = highlight.id

            guard
                let document = pdfView.document,
                let page = document.page(at: highlight.pageIndex)
            else { return }

            let selections = document.findString(
                highlight.query,
                withOptions: [.caseInsensitive, .diacriticInsensitive]
            )
            let pageSelections = selections.filter { selection in
                selection.pages.contains { $0 === page }
            }
            pdfView.highlightedSelections = pageSelections

            guard !pageSelections.isEmpty else {
                pdfView.go(to: page)
                loadDrawing(for: highlight.pageIndex)
                return
            }

            let selectedIndex = min(highlight.occurrenceIndex, pageSelections.count - 1)
            let selectedMatch = pageSelections[selectedIndex]
            pdfView.currentSelection = selectedMatch
            pdfView.go(to: selectedMatch)
            loadDrawing(for: highlight.pageIndex)
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
            enableOverlayHitTesting(in: pdfView)
            let overlayView = pageOverlayViews[pageIndex] ?? makeOverlayView(for: pageIndex, page: page)
            overlayView.imageView.image = overlayImage(for: pageIndex, page: page)
            overlayView.imageView.isHidden = !containerCanvasHiddenState()
            overlayView.configure(
                pageIndex: pageIndex,
                notes: notesByPage[pageIndex] ?? [],
                dialogueHighlights: dialogueHighlights(for: pageIndex, page: page),
                onMoveNote: { [weak self] note, anchor in
                    self?.moveNote(note, to: anchor)
                },
                onDeleteNote: { [weak self] note in
                    self?.deleteNote(note)
                },
                onSelectHighlight: { [weak self] sequenceIndex in
                    guard let self,
                          let turn = self.dialogueTurnsByPage[pageIndex]?.first(where: { $0.sequenceIndex == sequenceIndex })
                    else { return }
                    self.onDialogueTurnSelected?(turn)
                }
            )
            return overlayView
        }

        func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
            overlayView.isUserInteractionEnabled = true
            enableOverlayHitTesting(in: pdfView)
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let pageIndex = pdfView.document?.index(for: page) else { return }
            pageOverlayViews[pageIndex]?.imageView.image = overlayImage(for: pageIndex, page: page)
        }

        private func enableOverlayHitTesting(in pdfView: PDFView) {
            pdfView.documentView?.subviews.forEach { subview in
                let className = String(describing: type(of: subview))
                if className.contains("PDFPageView") {
                    subview.isUserInteractionEnabled = true
                }
            }
        }

        private func makeOverlayView(for pageIndex: Int, page: PDFPage) -> ReaderPageOverlayView {
            let overlayView = ReaderPageOverlayView()
            overlayView.backgroundColor = .clear
            overlayView.imageView.image = overlayImage(for: pageIndex, page: page)
            pageOverlayViews[pageIndex] = overlayView
            return overlayView
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

            let overlayView = pageOverlayViews[pageIndex] ?? makeOverlayView(for: pageIndex, page: page)
            overlayView.imageView.image = overlayImage(for: pageIndex, page: page)
            overlayView.imageView.isHidden = hidden
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

        private func refreshVisibleNoteMarkers() {
            for (pageIndex, overlayView) in pageOverlayViews {
                let page = containerView?.pdfView.document?.page(at: pageIndex)
                overlayView.configure(
                    pageIndex: pageIndex,
                    notes: notesByPage[pageIndex] ?? [],
                    dialogueHighlights: page.map { dialogueHighlights(for: pageIndex, page: $0) } ?? [],
                    onMoveNote: { [weak self] note, anchor in
                        self?.moveNote(note, to: anchor)
                    },
                    onDeleteNote: { [weak self] note in
                        self?.deleteNote(note)
                    },
                    onSelectHighlight: { [weak self] sequenceIndex in
                        guard let self,
                              let turn = self.dialogueTurnsByPage[pageIndex]?.first(where: { $0.sequenceIndex == sequenceIndex })
                        else { return }
                        self.onDialogueTurnSelected?(turn)
                    }
                )
            }
        }

        private func dialogueHighlights(for pageIndex: Int, page: PDFPage) -> [PDFDialoguePageHighlight] {
            guard dialogueHighlightSettings.isEnabled,
                  dialogueHighlightSettings.activeTurnSequenceIndex != nil || !dialogueHighlightSettings.isMuteAll
            else { return [] }

            let turns = (dialogueTurnsByPage[pageIndex] ?? []).filter {
                dialogueHighlightSettings.shouldShow(turn: $0)
            }

            return turns.compactMap { turn in
                let rects = dialogueRects(for: turn, page: page)
                guard !rects.isEmpty else { return nil }

                return PDFDialoguePageHighlight(
                    id: turn.id,
                    sequenceIndex: turn.sequenceIndex,
                    characterName: turn.characterName,
                    pageBounds: page.bounds(for: .mediaBox),
                    rects: rects,
                    color: PDFDialogueHighlightPalette.uiColor(
                        for: turn.characterName,
                        allCharacters: dialogueCharacters,
                        alpha: 0.24
                    )
                )
            }
        }

        private func dialogueRects(for turn: ScriptDialogueTurn, page: PDFPage) -> [CGRect] {
            if let cached = dialogueHighlightRectCache[turn.sequenceIndex] {
                return cached
            }

            let dialogue = turn.dialogue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let selection = page.selection(forNormalizedQuery: dialogue) {
                let rects = mergedDialogueRects(selection.highlightLineRects(for: page))
                if !rects.isEmpty {
                    dialogueHighlightRectCache[turn.sequenceIndex] = rects
                    return rects
                }
            }

            var rects: [CGRect] = []
            for candidate in dialogueSearchCandidates(for: turn) {
                guard let selection = page.selection(forNormalizedQuery: candidate) else { continue }
                rects.append(contentsOf: selection.highlightLineRects(for: page))
            }

            rects = mergedDialogueRects(rects)
            if !rects.isEmpty {
                dialogueHighlightRectCache[turn.sequenceIndex] = rects
                return rects
            }

            dialogueHighlightRectCache[turn.sequenceIndex] = []
            return []
        }

        private func dialogueSearchCandidates(for turn: ScriptDialogueTurn) -> [String] {
            let dialogue = turn.dialogue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dialogue.isEmpty else { return [] }

            var candidates: [String] = []

            if let sentenceEnd = dialogue.firstIndex(where: { ".!?".contains($0) }) {
                let firstSentence = String(dialogue[...sentenceEnd])
                if firstSentence.count >= 16 {
                    candidates.append(firstSentence)
                }
            }

            let words = dialogue.split(separator: " ")
            if words.count >= 4 {
                let chunkSize = 12
                let step = 10
                var index = 0

                while index < words.count {
                    let end = min(index + chunkSize, words.count)
                    let chunk = words[index..<end].joined(separator: " ")
                    if chunk.count >= 16 {
                        candidates.append(chunk)
                    }

                    if end == words.count { break }
                    index += step
                }

                if words.count > chunkSize {
                    let tail = words.suffix(min(chunkSize, words.count)).joined(separator: " ")
                    candidates.append(tail)
                }
            }

            return Array(NSOrderedSet(array: candidates).compactMap { $0 as? String })
        }

        private func mergedDialogueRects(_ rects: [CGRect]) -> [CGRect] {
            let validRects = rects
                .filter { $0.width > 2 && $0.height > 2 }
                .sorted {
                    if abs($0.midY - $1.midY) > 3 {
                        return $0.midY > $1.midY
                    }
                    return $0.minX < $1.minX
                }

            return validRects.reduce(into: [CGRect]()) { merged, rect in
                guard let last = merged.last else {
                    merged.append(rect)
                    return
                }

                let verticalOverlap = min(last.maxY, rect.maxY) - max(last.minY, rect.minY)
                let sameLine = verticalOverlap >= min(last.height, rect.height) * 0.45
                let closeEnough = rect.minX <= last.maxX + 18

                if sameLine && closeEnough {
                    merged[merged.count - 1] = last.union(rect)
                } else {
                    merged.append(rect)
                }
            }
        }

        private func moveNote(_ note: ScriptNote, to anchor: NotePageAnchor) {
            note.rectString = anchor.storageString
            note.updatedAt = Date()
            try? modelContext?.save()
        }

        private func deleteNote(_ note: ScriptNote) {
            let pageIndex = note.pageIndex
            notesByPage[pageIndex]?.removeAll { $0.id == note.id }
            modelContext?.delete(note)
            try? modelContext?.save()
            refreshVisibleNoteMarkers()
        }

        private func installPageObserverIfNeeded(for pdfView: PDFView) {
            guard pageChangedObserver == nil else { return }

            pageChangedObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard
                        let self,
                        let pdfView = notification.object as? PDFView,
                        let page = pdfView.currentPage
                    else { return }

                    self.persistCurrentCanvasIfNeeded()
                    let pageIndex = pdfView.document?.index(for: page) ?? self.loadedPageIndex
                    self.loadDrawing(for: pageIndex)
                    self.onPageChanged?(pageIndex)
                    let totalPages = pdfView.document?.pageCount ?? 0
                    self.updateReadingSession(pageIndex: pageIndex, totalPages: totalPages)
                }
            }
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

        private func updateReadingSession(pageIndex: Int, totalPages: Int) {
            guard let document, let modelContext else { return }
            ReadingSessionService.update(
                documentId: document.id,
                pageIndex: pageIndex,
                totalPages: totalPages,
                in: modelContext
            )
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
        canvasView.isHidden = true
        canvasView.isUserInteractionEnabled = false

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

private extension PDFPage {
    func selection(forNormalizedQuery query: String) -> PDFSelection? {
        guard let pageText = string else { return nil }
        let normalizedPage = NormalizedTextMap(source: pageText)
        let normalizedQuery = query.normalizedForPDFSearch
        guard !normalizedQuery.isEmpty,
              let normalizedRange = normalizedPage.text.range(
                of: normalizedQuery,
                options: [.caseInsensitive, .diacriticInsensitive]
              )
        else { return nil }

        let startOffset = normalizedPage.text.distance(
            from: normalizedPage.text.startIndex,
            to: normalizedRange.lowerBound
        )
        let endOffset = normalizedPage.text.distance(
            from: normalizedPage.text.startIndex,
            to: normalizedRange.upperBound
        )

        guard startOffset >= 0,
              endOffset > startOffset,
              startOffset < normalizedPage.sourceIndices.count,
              endOffset - 1 < normalizedPage.sourceIndices.count
        else { return nil }

        let sourceStart = normalizedPage.sourceIndices[startOffset]
        let sourceEnd = pageText.index(after: normalizedPage.sourceIndices[endOffset - 1])
        let range = NSRange(sourceStart..<sourceEnd, in: pageText)
        return selection(for: range)
    }
}

private extension PDFSelection {
    func highlightLineRects(for page: PDFPage) -> [CGRect] {
        let lineSelections = selectionsByLine()
        let rects = lineSelections.map { $0.bounds(for: page) }

        if rects.contains(where: { $0.width > 2 && $0.height > 2 }) {
            return rects
        }

        return [bounds(for: page)]
    }
}

private struct NormalizedTextMap {
    let text: String
    let sourceIndices: [String.Index]

    init(source: String) {
        var normalized = ""
        var indices: [String.Index] = []
        var previousWasWhitespace = true

        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]

            if character.isWhitespace {
                if !previousWasWhitespace {
                    normalized.append(" ")
                    indices.append(index)
                    previousWasWhitespace = true
                }
            } else {
                normalized.append(character)
                indices.append(index)
                previousWasWhitespace = false
            }

            index = source.index(after: index)
        }

        while normalized.last == " " {
            normalized.removeLast()
            indices.removeLast()
        }

        self.text = normalized
        self.sourceIndices = indices
    }
}

private extension String {
    var normalizedForPDFSearch: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private struct NotePageAnchor {
    var x: CGFloat
    var y: CGFloat

    var storageString: String {
        String(format: "%.3f,%.3f", Double(x), Double(y))
    }

    static func parse(_ string: String?) -> NotePageAnchor? {
        guard let string else { return nil }
        let parts = string.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return NotePageAnchor(
            x: CGFloat(parts[0]).clamped(to: 0...1),
            y: CGFloat(parts[1]).clamped(to: 0...1)
        )
    }

    static func fallback(for index: Int) -> NotePageAnchor {
        NotePageAnchor(x: 0.88, y: min(0.14 + CGFloat(index % 6) * 0.08, 0.58))
    }
}

private struct PDFDialoguePageHighlight: Identifiable {
    let id: UUID
    let sequenceIndex: Int
    let characterName: String
    let pageBounds: CGRect
    let rects: [CGRect]
    let color: UIColor
}

private final class ReaderPageOverlayView: UIView {
    let imageView = UIImageView()
    private let dialogueHighlightView = PDFDialogueHighlightView()
    private var markerViews: [UUID: NoteMarkerView] = [:]
    private var noteIDs: [UUID] = []
    private var markerAnchors: [UUID: NotePageAnchor] = [:]
    private var dialogueHighlights: [PDFDialoguePageHighlight] = []
    private var onSelectHighlight: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        pageIndex: Int,
        notes: [ScriptNote],
        dialogueHighlights: [PDFDialoguePageHighlight],
        onMoveNote: @escaping (ScriptNote, NotePageAnchor) -> Void,
        onDeleteNote: @escaping (ScriptNote) -> Void,
        onSelectHighlight: @escaping (Int) -> Void
    ) {
        self.dialogueHighlights = dialogueHighlights
        self.onSelectHighlight = onSelectHighlight
        dialogueHighlightView.highlights = dialogueHighlights

        let currentIDs = Set(notes.map(\.id))
        let removedIDs = markerViews.keys.filter { !currentIDs.contains($0) }
        for id in removedIDs {
            guard let markerView = markerViews[id] else { continue }
            markerView.removeFromSuperview()
            markerViews[id] = nil
            markerAnchors[id] = nil
        }

        noteIDs = notes.map(\.id)
        for (index, note) in notes.enumerated() {
            let anchor = NotePageAnchor.parse(note.rectString) ?? .fallback(for: index)
            markerAnchors[note.id] = anchor

            let markerView = markerViews[note.id] ?? NoteMarkerView()
            if markerViews[note.id] == nil {
                addSubview(markerView)
                markerViews[note.id] = markerView
            }

            markerView.configure(
                note: note,
                pageNumber: pageIndex + 1,
                anchor: anchor,
                onMove: { [weak self, weak note] newAnchor in
                    guard let self, let note else { return }
                    self.markerAnchors[note.id] = newAnchor
                    onMoveNote(note, newAnchor)
                    self.setNeedsLayout()
                },
                onDelete: { [weak note] in
                    guard let note else { return }
                    onDeleteNote(note)
                }
            )
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dialogueHighlightView.frame = bounds
        imageView.frame = bounds

        for id in noteIDs {
            guard let markerView = markerViews[id],
                  let anchor = markerAnchors[id] else { continue }
            let size = markerView.intrinsicContentSize
            markerView.frame = CGRect(
                x: bounds.width * anchor.x - size.width / 2,
                y: bounds.height * anchor.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }

        for subview in subviews.reversed() where subview !== imageView && subview !== dialogueHighlightView {
            guard subview.isUserInteractionEnabled, !subview.isHidden, subview.alpha > 0.01 else { continue }
            let convertedPoint = subview.convert(point, from: self)
            if let hitView = subview.hitTest(convertedPoint, with: event) {
                return hitView
            }
        }

        if highlightedSequenceIndex(at: point) != nil {
            return self
        }

        return nil
    }

    private func setup() {
        dialogueHighlightView.backgroundColor = .clear
        dialogueHighlightView.isUserInteractionEnabled = false
        addSubview(dialogueHighlightView)

        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        guard let sequenceIndex = highlightedSequenceIndex(at: point) else { return }
        onSelectHighlight?(sequenceIndex)
    }

    private func highlightedSequenceIndex(at point: CGPoint) -> Int? {
        for highlight in dialogueHighlights.reversed() {
            for pageRect in highlight.rects {
                let overlayRect = overlayRect(for: pageRect, pageBounds: highlight.pageBounds)
                    .insetBy(dx: -10, dy: -8)
                if overlayRect.contains(point) {
                    return highlight.sequenceIndex
                }
            }
        }

        return nil
    }

    private func overlayRect(for pageRect: CGRect, pageBounds: CGRect) -> CGRect {
        guard pageBounds.width > 0, pageBounds.height > 0 else { return .zero }

        let scaleX = bounds.width / pageBounds.width
        let scaleY = bounds.height / pageBounds.height
        let x = (pageRect.minX - pageBounds.minX) * scaleX
        let y = (pageBounds.maxY - pageRect.maxY) * scaleY

        return CGRect(
            x: x,
            y: y,
            width: pageRect.width * scaleX,
            height: pageRect.height * scaleY
        )
    }
}

private final class PDFDialogueHighlightView: UIView {
    var highlights: [PDFDialoguePageHighlight] = [] {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for highlight in highlights {
            context.setFillColor(highlight.color.cgColor)

            for pageRect in highlight.rects {
                let overlayRect = overlayRect(for: pageRect, pageBounds: highlight.pageBounds)
                    .insetBy(dx: -4, dy: -3)
                UIBezierPath(roundedRect: overlayRect, cornerRadius: 4).fill()
            }
        }
    }

    private func overlayRect(for pageRect: CGRect, pageBounds: CGRect) -> CGRect {
        guard pageBounds.width > 0, pageBounds.height > 0 else { return .zero }

        let scaleX = bounds.width / pageBounds.width
        let scaleY = bounds.height / pageBounds.height
        let x = (pageRect.minX - pageBounds.minX) * scaleX
        let y = (pageBounds.maxY - pageRect.maxY) * scaleY

        return CGRect(
            x: x,
            y: y,
            width: pageRect.width * scaleX,
            height: pageRect.height * scaleY
        )
    }
}

private final class NoteMarkerView: UIControl, UIGestureRecognizerDelegate {
    private let iconView = UIImageView(image: UIImage(systemName: "note.text"))
    private let pageLabel = UILabel()
    private var note: ScriptNote?
    private var onMove: ((NotePageAnchor) -> Void)?
    private var onDelete: (() -> Void)?
    private var dragStartCenter: CGPoint = .zero
    private weak var activeScrollView: UIScrollView?

    override var intrinsicContentSize: CGSize {
        CGSize(width: 58, height: 34)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        note: ScriptNote,
        pageNumber: Int,
        anchor: NotePageAnchor,
        onMove: @escaping (NotePageAnchor) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.note = note
        self.onMove = onMove
        self.onDelete = onDelete
        pageLabel.text = "p\(pageNumber)"
        accessibilityLabel = "Note on page \(pageNumber)"
        accessibilityHint = "Drag to move this note marker. Long press to delete it."
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.frame = CGRect(x: 10, y: 7, width: 20, height: 20)
        pageLabel.frame = CGRect(x: 32, y: 0, width: bounds.width - 38, height: bounds.height)
    }

    private func setup() {
        backgroundColor = UIColor.systemOrange.withAlphaComponent(0.92)
        isExclusiveTouch = true
        layer.cornerRadius = 13
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)

        pageLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        pageLabel.textColor = .white
        addSubview(pageLabel)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.cancelsTouchesInView = true
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let container = superview else { return }

        switch recognizer.state {
        case .began:
            dragStartCenter = center
            activeScrollView = nearestScrollView()
            activeScrollView?.panGestureRecognizer.isEnabled = false
        case .changed, .ended:
            let translation = recognizer.translation(in: container)
            let halfWidth = bounds.width / 2
            let halfHeight = bounds.height / 2
            let newCenter = CGPoint(
                x: (dragStartCenter.x + translation.x).clamped(to: halfWidth...(container.bounds.width - halfWidth)),
                y: (dragStartCenter.y + translation.y).clamped(to: halfHeight...(container.bounds.height - halfHeight))
            )
            center = newCenter

            if recognizer.state == .ended {
                onMove?(
                    NotePageAnchor(
                        x: (newCenter.x / max(container.bounds.width, 1)).clamped(to: 0...1),
                        y: (newCenter.y / max(container.bounds.height, 1)).clamped(to: 0...1)
                    )
                )
            }
            if recognizer.state == .ended {
                activeScrollView?.panGestureRecognizer.isEnabled = true
                activeScrollView = nil
            }
        case .cancelled, .failed:
            activeScrollView?.panGestureRecognizer.isEnabled = true
            activeScrollView = nil
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: "Delete Note",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.onDelete?()
                }
            ])
        }
    }

    private func nearestScrollView() -> UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
