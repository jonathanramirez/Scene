import SwiftUI

struct ReaderSidebarBookmarkSection: View {
    let bookmarks: [ScriptBookmark]
    let onJump: (Int) -> Void
    let onDelete: (ScriptBookmark) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReaderSidebarSectionHeader("Bookmarks") {
                Text("\(bookmarks.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(bookmarks) { bookmark in
                    row(bookmark)
                }
            }
        }
    }

    // MARK: - Row

    private func row(_ bookmark: ScriptBookmark) -> some View {
        Button {
            ReaderSidebarHaptic.fire(.light)
            onJump(bookmark.pageIndex)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.label ?? "Page \(bookmark.pageIndex + 1)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if bookmark.label != nil {
                        Text("Page \(bookmark.pageIndex + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .hoverEffect(.lift)
        }
        .buttonStyle(PressableCardStyle())
        .contextMenu {
            Button(role: .destructive) {
                ReaderSidebarHaptic.fire(.rigid)
                onDelete(bookmark)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
