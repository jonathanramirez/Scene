import SwiftUI
import UniformTypeIdentifiers

struct ImportButton: ToolbarContent {
    @Binding var isPresented: Bool
    let isBusy: Bool
    let onImportSelected: (URL) -> Void
    let onImportFailed: (Error) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresented = true
            } label: {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(isBusy)
            .accessibilityLabel("Import PDF")
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    onImportSelected(url)
                case .failure(let error):
                    guard !error.isUserCancellation else { return }
                    onImportFailed(error)
                }
            }
        }
    }
}

private extension Error {
    var isUserCancellation: Bool {
        let nsError = self as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}
