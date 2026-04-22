import SwiftUI

struct LyricsSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lyricsIsDarkMode") private var isDarkMode = true
    @AppStorage("lyricsFontSizeStep") private var fontSizeStep: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    themeCard
                    fontSizeCard
                    previewCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lyrics Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Cards

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Theme")

            themePicker
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }

    private var fontSizeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Text Size") {
                Text(fontSizeName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            fontSizeControl
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Preview")

            lyricsPreview
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Theme Picker

    private var themePicker: some View {
        HStack(spacing: 12) {
            themeOption(
                label: "Dark",
                icon: "moon.fill",
                isSelected: isDarkMode,
                cardBg: .black,
                cardFg: .white
            ) { isDarkMode = true }

            themeOption(
                label: "Read",
                icon: "sun.max.fill",
                isSelected: !isDarkMode,
                cardBg: LyricsColors.readBg,
                cardFg: LyricsColors.readText
            ) { isDarkMode = false }
        }
        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    }

    private func themeOption(
        label: String,
        icon: String,
        isSelected: Bool,
        cardBg: Color,
        cardFg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(cardBg)
                    .frame(height: 72)
                    .overlay {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(cardFg)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected ? Color.orange : Color.secondary.opacity(0.25),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    }

                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .orange : .primary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Font Size

    private var fontSizeControl: some View {
        HStack(spacing: 14) {
            Text("A")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Slider(
                value: Binding(
                    get: { Double(fontSizeStep) },
                    set: { fontSizeStep = Int($0.rounded()) }
                ),
                in: -2...4,
                step: 1
            )
            .tint(.orange)

            Text("A")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 24)
        }
    }

    private var fontSizeName: String {
        switch fontSizeStep {
        case -2: return "Extra Small"
        case -1: return "Small"
        case  0: return "Default"
        case  1: return "Large"
        case  2: return "Extra Large"
        case  3: return "Huge"
        case  4: return "Maximum"
        default: return "Default"
        }
    }

    // MARK: - Live Preview

    private var lyricsPreview: some View {
        ZStack {
            isDarkMode ? Color.black : LyricsColors.readBg

            VStack(alignment: .leading, spacing: 0) {
                previewRow(character: "SARAH",   dialogue: "I can't believe you came back.",  state: .past)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                previewRow(character: "YOU",     dialogue: "Tap to reveal your line",         state: .active)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                previewRow(character: "SARAH",   dialogue: "It's too late. You know that.",    state: .future)
                    .padding(.horizontal, 22).padding(.vertical, 12)
            }
            .padding(.vertical, 10)
        }
        .frame(minHeight: 210)
        .animation(.easeInOut(duration: 0.25), value: isDarkMode)
        .animation(.easeInOut(duration: 0.2), value: fontSizeStep)
    }

    private enum PreviewState { case past, active, future }

    @ViewBuilder
    private func previewRow(character: String, dialogue: String, state: PreviewState) -> some View {
        let isActive = state == .active
        let isPast   = state == .past
        let isMe     = character == "YOU"
        let offset   = CGFloat(fontSizeStep) * 2

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if isMe && isActive {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                }
                Text(character)
                    .font(.caption).fontWeight(.semibold).tracking(1.0)
                    .foregroundStyle(LyricsColors.charName(isDark: isDarkMode, isActive: isActive, isMe: isMe, isPast: isPast))
            }

            Text(dialogue)
                .font(.system(size: previewFontSize(isActive: isActive, isPast: isPast, offset: offset)))
                .fontWeight(isActive ? .semibold : .regular)
                .italic(isActive && isMe)
                .foregroundStyle(LyricsColors.dialogue(isDark: isDarkMode, isActive: isActive, isMe: isMe, isPast: isPast))
                .fixedSize(horizontal: false, vertical: true)
        }
        .scaleEffect(isActive ? 1.0 : 0.88, anchor: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
    }

    private func previewFontSize(isActive: Bool, isPast: Bool, offset: CGFloat) -> CGFloat {
        (isActive ? 20 : (isPast ? 14 : 18)) + offset
    }
}

// MARK: - Shared Color Helpers

enum LyricsColors {
    static let readBg   = Color(red: 0.97, green: 0.95, blue: 0.88)
    static let readText = Color(red: 0.12, green: 0.08, blue: 0.04)

    static func charName(isDark: Bool, isActive: Bool, isMe: Bool, isPast: Bool) -> Color {
        if isActive { return isMe ? .orange : .blue }
        if isDark   { return .white.opacity(isPast ? 0.20 : 0.35) }
        return readText.opacity(isPast ? 0.25 : 0.50)
    }

    static func dialogue(isDark: Bool, isActive: Bool, isMe: Bool, isPast: Bool) -> Color {
        if isActive { return isMe ? .orange : (isDark ? .white : readText) }
        if isDark   { return .white.opacity(isPast ? 0.20 : 0.45) }
        return readText.opacity(isPast ? 0.28 : 0.60)
    }

    static func hiddenLine(isDark: Bool, isPast: Bool) -> Color {
        .orange.opacity(isDark ? (isPast ? 0.18 : 0.28) : (isPast ? 0.30 : 0.55))
    }

    static func revealHint(isDark: Bool) -> Color {
        .orange.opacity(isDark ? 0.60 : 0.72)
    }

    static func control(isDark: Bool) -> Color {
        isDark ? .white.opacity(0.45) : readText.opacity(0.55)
    }

    static func bottomGradient(isDark: Bool) -> LinearGradient {
        let solid: Color = isDark ? .black : readBg
        return LinearGradient(
            colors: [.clear, solid.opacity(0.85), solid],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
