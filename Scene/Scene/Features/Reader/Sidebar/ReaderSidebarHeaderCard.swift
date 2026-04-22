import SwiftUI

struct ReaderSidebarHeaderCard: View {
    let title: String
    let currentPageIndex: Int
    let pageCount: Int
    let currentScene: ScriptScene?
    let parseResult: ScriptParseResult?
    let characterCount: Int
    let isParsing: Bool
    let indexedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)

            if let scene = currentScene {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text("Scene #\(scene.index) · \(scene.heading)")
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.orange)
            }

            progressBlock

            if let pr = parseResult {
                HStack(spacing: 6) {
                    statChip(value: "\(pr.dialogueTurns.count)", label: "turns")
                    statChip(value: "\(characterCount)", label: "chars")
                    statChip(value: "\(pr.scenes.count)", label: "scenes")
                }
            }

            indexStatusPill
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Progress

    private var progressBlock: some View {
        let total = max(pageCount, 1)
        let current = min(currentPageIndex + 1, total)
        let progress = Double(current) / Double(total)
        return VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress).tint(.orange)
            HStack {
                Text("Page \(current) of \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Stat chip

    private func statChip(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.caption.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    // MARK: - Index status pill

    @ViewBuilder
    private var indexStatusPill: some View {
        let (icon, text, color): (String, String, Color) = {
            if isParsing {
                return ("gearshape", "Indexing…", .orange)
            }
            if let at = indexedAt {
                return ("checkmark.circle.fill",
                        "Indexed \(at.formatted(.relative(presentation: .named)))",
                        .green)
            }
            return ("circle.dashed", "Not indexed", .secondary)
        }()
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(color)
    }
}
