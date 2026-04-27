import SwiftData
import SwiftUI
internal import os

private enum LibraryDisplayMode: String {
    case recent
    case alphabetical
}

private struct LibraryDocumentSection: Identifiable {
    let id: String
    let title: String
    let documents: [ScriptDocument]
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScriptDocument.createdAt, order: .reverse) private var docs: [ScriptDocument]
    @Query(sort: \ScriptReadingSession.updatedAt, order: .reverse) private var sessions: [ScriptReadingSession]
    @AppStorage("libraryDisplayMode") private var libraryDisplayModeRaw = LibraryDisplayMode.recent.rawValue
    @State private var navigationPath: [UUID] = []
    @State private var searchQuery = ""
    @State private var isFileImporterPresented = false
    @State private var isImportInProgress = false
    @State private var importErrorMessage: String?
    @State private var isShowingImportError = false
    @State private var lastImportedDocument: ScriptDocument?
    @State private var documentPendingDeletion: ScriptDocument?
    @State private var documentBeingEdited: ScriptDocument?
    @State private var isShowingDeleteConfirmation = false
    @State private var deletionErrorMessage: String?
    @State private var isShowingDeletionError = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            libraryList
                .navigationTitle(libraryTitle)
                .searchable(
                    text: $searchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Find"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        sortModeMenu
                    }

                    ImportButton(
                        isPresented: $isFileImporterPresented,
                        isBusy: isImportInProgress,
                        onImportSelected: importPDF,
                        onImportFailed: presentImportError
                    )
                }
                .navigationDestination(for: UUID.self) { documentID in
                    if let document = document(for: documentID) {
                        ScriptDetailView(document: document)
                    } else {
                        missingImportedDocument
                    }
                }
                .confirmationDialog(
                    "Delete script?",
                    isPresented: $isShowingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        confirmDelete()
                    }
                    Button("Cancel", role: .cancel) {
                        cancelDelete()
                    }
                } message: {
                    Text("This will remove the uploaded PDF and its related notes, drawings, bookmarks, and reading progress.")
                }
                .alert("Delete failed", isPresented: $isShowingDeletionError) {
                    Button("OK", role: .cancel) {
                        deletionErrorMessage = nil
                    }
                } message: {
                    Text(deletionErrorMessage ?? AppError.deleteFailed.localizedDescription)
                }
                .alert("Import failed", isPresented: $isShowingImportError) {
                    Button("OK", role: .cancel) {
                        importErrorMessage = nil
                    }
                } message: {
                    Text(importErrorMessage ?? AppError.importFailed.localizedDescription)
                }
                .sheet(item: $documentBeingEdited) { doc in
                    EditMetadataView(document: doc)
                }
                .overlay {
                    if isImportInProgress {
                        importProgressOverlay
                    }
                }
        }
    }

    @ViewBuilder
    private var libraryList: some View {
        if docs.isEmpty {
            emptyState
        } else {
            List {
                if filteredDocuments.isEmpty {
                    noResultsState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    switch selectedDisplayMode {
                    case .recent:
                        recentSections
                    case .alphabetical:
                        alphabeticalSections
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("No Scripts Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Import a screenplay PDF to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                isFileImporterPresented = true
            } label: {
                if isImportInProgress {
                    Label("Importing PDF", systemImage: "hourglass")
                        .padding(.horizontal, 6)
                } else {
                    Label("Import PDF", systemImage: "plus.circle.fill")
                        .padding(.horizontal, 6)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isImportInProgress)
            .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var sortModeMenu: some View {
        Menu {
            Button {
                libraryDisplayModeRaw = LibraryDisplayMode.recent.rawValue
            } label: {
                Label("Recent", systemImage: selectedDisplayMode == .recent ? "checkmark" : "clock.arrow.circlepath")
            }

            Button {
                libraryDisplayModeRaw = LibraryDisplayMode.alphabetical.rawValue
            } label: {
                Label("ABC", systemImage: selectedDisplayMode == .alphabetical ? "checkmark" : "textformat.abc")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedDisplayMode == .recent ? "clock.arrow.circlepath" : "textformat.abc")
                    .font(.caption.weight(.semibold))
                Text(sortModeTitle)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .accessibilityLabel("Library order")
        .accessibilityValue(sortModeTitle)
    }

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No scripts found", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Try another title or clear the search.")
        }
        .padding(.vertical, 36)
    }

    @ViewBuilder
    private var recentSections: some View {
        if !recentlyOpenedDocuments.isEmpty {
            Section {
                ForEach(recentlyOpenedDocuments) { doc in
                    scriptRow(for: doc)
                }
            } header: {
                sectionHeader("Recently Opened", count: recentlyOpenedDocuments.count)
            }
        }

        if !recentlyAddedDocuments.isEmpty {
            Section {
                ForEach(recentlyAddedDocuments) { doc in
                    scriptRow(for: doc)
                }
            } header: {
                sectionHeader("Recently Added", count: recentlyAddedDocuments.count)
            }
        }
    }

    @ViewBuilder
    private var alphabeticalSections: some View {
        ForEach(alphabeticalDocumentSections) { section in
            Section {
                ForEach(section.documents) { doc in
                    scriptRow(for: doc)
                }
            } header: {
                sectionHeader(section.title, count: section.documents.count)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Text("\(count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.orange)

                VStack(spacing: 3) {
                    Text("Importing PDF")
                        .font(.headline)
                    Text("Copying it into Scene and reading page count.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(18)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }

    private var missingImportedDocument: some View {
        ContentUnavailableView {
            Label("Script unavailable", systemImage: "doc.badge.questionmark")
        } description: {
            Text("The imported script could not be opened from the library.")
        }
    }

    private func scriptRow(for document: ScriptDocument) -> some View {
        NavigationLink(value: document.id) {
            ScriptRowView(document: document)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .hoverEffect(.lift)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                promptDelete(for: document)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                documentBeingEdited = document
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                documentBeingEdited = document
            } label: {
                Label("Edit Metadata", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                promptDelete(for: document)
            } label: {
                Label("Delete Script", systemImage: "trash")
            }
        }
    }

    private func promptDelete(for document: ScriptDocument) {
        documentPendingDeletion = document
        isShowingDeleteConfirmation = true
    }

    private func cancelDelete() {
        documentPendingDeletion = nil
        isShowingDeleteConfirmation = false
    }

    private func importPDF(from url: URL) {
        guard !isImportInProgress else { return }

        isImportInProgress = true
        importErrorMessage = nil

        Task { @MainActor in
            await Task.yield()
            do {
                let document = try ScriptImportService().importPDF(from: url, into: context)
                lastImportedDocument = document
                isImportInProgress = false
                navigationPath = [document.id]
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                Log.importFlow.error("Import failed: \(String(describing: error))")
                isImportInProgress = false
                presentImportError(error)
            }
        }
    }

    private func presentImportError(_ error: Error) {
        importErrorMessage = error.localizedDescription
        isShowingImportError = true
    }

    private func document(for id: UUID) -> ScriptDocument? {
        docs.first { $0.id == id } ?? (lastImportedDocument?.id == id ? lastImportedDocument : nil)
    }

    private var selectedDisplayMode: LibraryDisplayMode {
        LibraryDisplayMode(rawValue: libraryDisplayModeRaw) ?? .recent
    }

    private var libraryTitle: String {
        selectedDisplayMode == .recent ? "Recents" : "All Scripts"
    }

    private var sortModeTitle: String {
        selectedDisplayMode == .recent ? "Recent" : "ABC"
    }

    private var filteredDocuments: [ScriptDocument] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return docs }

        return docs.filter { document in
            document.title.localizedCaseInsensitiveContains(query) ||
            document.originalFileName.localizedCaseInsensitiveContains(query)
        }
    }

    private var recentlyOpenedDocuments: [ScriptDocument] {
        filteredDocuments
            .filter { recentOpenDate(for: $0) != nil }
            .sorted {
                (recentOpenDate(for: $0) ?? .distantPast) > (recentOpenDate(for: $1) ?? .distantPast)
            }
    }

    private var recentlyAddedDocuments: [ScriptDocument] {
        let openedIDs = Set(recentlyOpenedDocuments.map(\.id))
        return filteredDocuments
            .filter { !openedIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var alphabeticalDocumentSections: [LibraryDocumentSection] {
        let grouped = Dictionary(grouping: filteredDocuments.sorted(by: documentTitleSort)) {
            alphabeticSectionTitle(for: $0.title)
        }

        return grouped.keys
            .sorted(by: sectionTitleSort)
            .map { key in
                LibraryDocumentSection(
                    id: key,
                    title: key,
                    documents: grouped[key] ?? []
                )
            }
    }

    private func recentOpenDate(for document: ScriptDocument) -> Date? {
        [
            document.lastOpenedAt,
            sessions.first { $0.documentId == document.id }?.updatedAt
        ]
        .compactMap { $0 }
        .max()
    }

    private func documentTitleSort(_ lhs: ScriptDocument, _ rhs: ScriptDocument) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func sectionTitleSort(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "#" { return false }
        if rhs == "#" { return true }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func alphabeticSectionTitle(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        if first.isLetter {
            return String(first).uppercased()
        }
        return "#"
    }

    private func confirmDelete() {
        guard let documentPendingDeletion else { return }

        do {
            try ScriptDeletionService.delete(document: documentPendingDeletion, from: context)
            cancelDelete()
        } catch {
            deletionErrorMessage = error.localizedDescription
            cancelDelete()
            isShowingDeletionError = true
        }
    }
}
