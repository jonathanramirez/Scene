import SwiftData
import SwiftUI

struct ScriptRowView: View {
    let document: ScriptDocument

    @Query(sort: \ScriptReadingSession.updatedAt, order: .reverse)
    private var allSessions: [ScriptReadingSession]

    private var session: ScriptReadingSession? {
        allSessions.first { $0.documentId == document.id }
    }

    var body: some View {
        HStack(spacing: 14) {
            scriptIcon
            info
        }
        .padding(.vertical, 4)
    }

    // MARK: - Icon

    private var scriptIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            document.iconColor.color.opacity(0.92),
                            document.iconColor.color.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 56)

            Image(systemName: "doc.text.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.9))
        }
        .shadow(color: document.iconColor.color.opacity(0.35), radius: 4, y: 2)
    }

    // MARK: - Text info

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 8) {
                metadataPill("\(document.pageCount) pages")
                metadataPill("~\(document.estimatedMinutes) min")

                Spacer()

                if let session, session.progress > 0 {
                    Text("\(Int(session.progress * 100))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            if let session, session.progress > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.mode == .firstRead ? "First read" : "Second read")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Page \(session.lastPageIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    ProgressView(value: session.progress)
                        .tint(.orange)
                        .scaleEffect(y: 0.7, anchor: .center)
                }
            }
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
}
