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
                .fill(document.iconColor.color)
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

            HStack(spacing: 6) {
                Text("\(document.pageCount) pages · ~\(document.estimatedMinutes) min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if let session, session.progress > 0 {
                    HStack(spacing: 4) {
                        Text(session.mode == .firstRead ? "1st" : "2nd")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(session.progress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let session, session.progress > 0 {
                ProgressView(value: session.progress)
                    .tint(.orange)
                    .scaleEffect(y: 0.7, anchor: .center)
            }
        }
    }
}
