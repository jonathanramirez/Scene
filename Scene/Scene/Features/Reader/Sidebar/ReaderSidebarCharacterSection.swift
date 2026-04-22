import SwiftUI

struct ReaderSidebarCharacterSection: View {
    let characters: [ScriptCharacter]
    let dialogueTurnCounts: [String: Int]
    let hasParseResult: Bool
    let onJump: (Int) -> Void
    let onInfo: (ScriptCharacter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReaderSidebarSectionHeader("Characters") {
                Text("\(characters.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                ForEach(characters) { c in
                    row(c)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Row

    private func row(_ c: ScriptCharacter) -> some View {
        HStack(spacing: 8) {
            Button {
                if let page = c.firstPage {
                    ReaderSidebarHaptic.fire(.light)
                    onJump(page)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(c.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let turns = dialogueTurnCounts[c.name] {
                        Text("\(turns)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hasParseResult {
                Button {
                    onInfo(c)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
