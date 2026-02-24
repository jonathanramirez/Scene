import SwiftUI

struct ScriptRowView: View {
    let document: ScriptDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title).font(.headline)
            Text("\(document.pageCount) pages • ~\(document.estimatedMinutes) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
