import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Reader") {
                    Toggle("Night Mode", isOn: .constant(false))
                    Toggle("First Read hints", isOn: .constant(true))
                }
                Section("About") {
                    LabeledContent("App", value: "Scene")
                    LabeledContent("Version", value: "0.1")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
