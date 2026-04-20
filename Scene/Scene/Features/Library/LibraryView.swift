import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScriptDocument.createdAt, order: .reverse) private var docs: [ScriptDocument]
    @State private var isImporting = false
    @State private var documentPendingDeletion: ScriptDocument?
    @State private var isShowingDeleteConfirmation = false
    @State private var deletionErrorMessage: String?
    @State private var isShowingDeletionError = false

    var body: some View {
        NavigationStack {
            libraryList
                .navigationTitle("Scene")
                .toolbar {
                    ImportButton(isPresented: $isImporting)
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
        }
    }

    private var libraryList: some View {
        List {
            ForEach(docs) { doc in
                scriptRow(for: doc)
            }
        }
    }

    private func scriptRow(for document: ScriptDocument) -> some View {
        NavigationLink {
            ReaderSplitView(document: document)
        } label: {
            ScriptRowView(document: document)
        }
        .swipeActions {
            Button(role: .destructive) {
                promptDelete(for: document)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
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
