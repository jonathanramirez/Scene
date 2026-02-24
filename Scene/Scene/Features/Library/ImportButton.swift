import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportButton: ToolbarContent {
    @Environment(\.modelContext) private var context
    @Binding var isPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresented = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let service = ScriptImportService()
                    _ = try service.importPDF(from: url, into: context)
                } catch {
                    Log.importFlow.error("Import failed: \(String(describing: error))")
                }
            }
        }
    }
}
