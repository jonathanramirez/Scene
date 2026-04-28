import SwiftUI

struct ReaderSidebarQuickActions: View {
    let hasIndex: Bool
    let isParsing: Bool
    let onPractice: () -> Void
    let onLyrics: () -> Void
    let onSearch: () -> Void
    let onAddBookmark: () -> Void
    let onBuildIndex: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReaderSidebarSectionHeader("Quick Actions")

            if !hasIndex {
                if isParsing {
                    indexingPlaceholder
                } else {
                    buildIndexPrompt
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                spacing: 10
            ) {
                if hasIndex {
                    card(icon: "mic.fill", label: "Practice", tint: .orange, action: onPractice)
                    card(icon: "text.alignleft", label: "Lyrics", tint: .purple, action: onLyrics)
                }

                card(icon: "magnifyingglass", label: "Search", tint: .blue, action: onSearch)
                card(icon: "bookmark", label: "Bookmark", tint: .orange, action: onAddBookmark)
            }
        }
    }

    // MARK: - Primary: quick action card

    private func card(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            ReaderSidebarHaptic.fire(.light)
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .hoverEffect(.lift)
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: - Placeholders

    private var indexingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.8)
            Text("Indexing script…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var buildIndexPrompt: some View {
        Button {
            ReaderSidebarHaptic.fire(.light)
            onBuildIndex()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build Index")
                        .font(.subheadline.weight(.semibold))
                    Text("Unlocks Practice & Lyrics")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.orange)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
            )
            .hoverEffect(.lift)
        }
        .buttonStyle(PressableCardStyle())
    }
}
