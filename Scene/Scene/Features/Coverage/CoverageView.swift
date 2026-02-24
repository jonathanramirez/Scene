import SwiftUI

struct CoverageView: View {
    @State private var logline = ""
    @State private var synopsis = ""
    @State private var comments = ""
    @State private var recommendation = ""

    var body: some View {
        Form {
            Section("Logline") { TextEditor(text: $logline).frame(minHeight: 80) }
            Section("Synopsis") { TextEditor(text: $synopsis).frame(minHeight: 120) }
            Section("Comments") { TextEditor(text: $comments).frame(minHeight: 120) }
            Section("Recommendation") { TextField("Pass / Consider / Recommend", text: $recommendation) }
        }
        .navigationTitle("Coverage")
    }
}
