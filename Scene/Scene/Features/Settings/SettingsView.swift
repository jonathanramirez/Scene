import SwiftUI

struct SettingsView: View {
    @AppStorage("lyricsIsDarkMode")   private var lyricsIsDarkMode   = true
    @AppStorage("lyricsFontSizeStep") private var lyricsFontSizeStep: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    readerCard
                    lyricsCard
                    libraryCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
        }
    }

    // MARK: - Reader

    private var readerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Reader")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "book.pages")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 36, height: 36)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("Reader defaults")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }

                Text("Scene keeps the reading experience intentionally minimal. Practice tools and annotations stay contextual so the script remains the focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Lyrics

    private var lyricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Lyrics Mode")

            NavigationLink {
                LyricsSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "textformat.size")
                        .font(.title3)
                        .foregroundStyle(.purple)
                        .frame(width: 36, height: 36)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appearance")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(lyricsSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .hoverEffect(.lift)
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    // MARK: - Library

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Library")

            VStack(spacing: 0) {
                infoRow(label: "Default experience", value: "Reader + Practice")
                Divider().padding(.leading, 14)
                infoRow(label: "Supported file type", value: "PDF screenplay")
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("About")

            VStack(spacing: 0) {
                infoRow(label: "App", value: "Scene")
                Divider().padding(.leading, 14)
                infoRow(label: "Version", value: "0.1")
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var lyricsSummary: String {
        let theme = lyricsIsDarkMode ? "Dark" : "Light"
        let size: String
        switch lyricsFontSizeStep {
        case -2: size = "XS"
        case -1: size = "S"
        case  0: size = "Default"
        case  1: size = "L"
        case  2: size = "XL"
        case  3: size = "XXL"
        case  4: size = "Max"
        default: size = "Default"
        }
        return "\(theme) · \(size)"
    }
}
