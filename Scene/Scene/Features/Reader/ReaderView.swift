import SwiftUI

struct ReaderView: View {
    let document: ScriptDocument
    @Binding var jumpToPage: Int?

    var body: some View {
        PDFKitRepresentedView(document: document, jumpToPage: $jumpToPage)
            .ignoresSafeArea(edges: .bottom)
    }
}
