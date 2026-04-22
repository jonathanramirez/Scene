import SwiftUI

struct ReaderSidebarSceneSection: View {
    let scenes: [ScriptScene]
    let isParsing: Bool
    let hasParseResult: Bool
    let currentSceneIndex: Int?
    let onJump: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReaderSidebarSectionHeader("Scenes") {
                if !scenes.isEmpty {
                    Text("\(scenes.count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if isParsing {
                ReaderSidebarInlineLoading(text: "Indexing…")
            } else if hasParseResult {
                if scenes.isEmpty {
                    ReaderSidebarEmptyState(
                        icon: "square.stack.3d.up",
                        message: "No scene headings found."
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(scenes) { scene in
                            row(scene)
                        }
                    }
                }
            } else {
                ReaderSidebarEmptyState(
                    icon: "square.stack.3d.up",
                    message: "Build the index to see scenes."
                )
            }
        }
    }

    // MARK: - Row

    private func row(_ scene: ScriptScene) -> some View {
        let isCurrent = currentSceneIndex == scene.index
        return Button {
            ReaderSidebarHaptic.fire(.light)
            onJump(scene.startPage)
        } label: {
            HStack(spacing: 10) {
                if isCurrent {
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }

                Text("#\(scene.index)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(isCurrent ? Color.white : .secondary)
                    .background(
                        Capsule().fill(isCurrent ? Color.orange : Color.secondary.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.heading)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text("Page \(scene.startPage + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, isCurrent ? 8 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? Color.orange.opacity(0.10) : Color(.secondarySystemGroupedBackground))
            )
            .animation(.easeInOut(duration: 0.25), value: isCurrent)
            .hoverEffect(.lift)
        }
        .buttonStyle(PressableCardStyle())
    }
}
