import SwiftData
import SwiftUI

struct EditMetadataView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let document: ScriptDocument

    @State private var title: String
    @State private var selectedColor: ScriptIconColor

    init(document: ScriptDocument) {
        self.document = document
        _title = State(initialValue: document.title)
        _selectedColor = State(initialValue: document.iconColor)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Script title", text: $title)
                        .autocorrectionDisabled()
                }

                Section {
                    colorPicker
                } header: {
                    Text("Library Icon Color")
                } footer: {
                    Text("Color shown on the script's icon in your library.")
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 0) {
            ForEach(ScriptIconColor.allCases) { iconColor in
                Button {
                    selectedColor = iconColor
                } label: {
                    ZStack {
                        Circle()
                            .fill(iconColor.color)
                            .frame(width: 36, height: 36)

                        if selectedColor == iconColor {
                            Circle()
                                .strokeBorder(.white, lineWidth: 2.5)
                                .frame(width: 36, height: 36)
                            Circle()
                                .strokeBorder(iconColor.color.opacity(0.5), lineWidth: 1)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document.title = trimmed
        document.iconColor = selectedColor
        try? context.save()
        dismiss()
    }
}
