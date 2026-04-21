import SwiftUI

struct SettingsView: View {
    @AppStorage("lyricsIsDarkMode")   private var lyricsIsDarkMode   = true
    @AppStorage("lyricsFontSizeStep") private var lyricsFontSizeStep: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Reader") {
                    Toggle("First Read hints", isOn: .constant(true))
                }

                Section("Lyrics Mode") {
                    NavigationLink {
                        LyricsSettingsView()
                    } label: {
                        HStack {
                            Label("Appearance", systemImage: "textformat.size")
                            Spacer()
                            Text(lyricsSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Scene")
                    LabeledContent("Version", value: "0.1")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var lyricsSummary: String {
        let theme = lyricsIsDarkMode ? "Dark" : "Read"
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
