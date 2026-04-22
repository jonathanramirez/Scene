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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    titleCard
                    colorCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
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

    // MARK: - Cards

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Title")

            TextField("Script title", text: $title)
                .autocorrectionDisabled()
                .font(.body)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Library Icon Color")

            VStack(alignment: .leading, spacing: 10) {
                colorPicker

                Text("Color shown on the script's icon in your library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 0) {
            ForEach(ScriptIconColor.allCases) { iconColor in
                Button {
                    ReaderSidebarHaptic.fire(.light)
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
                .hoverEffect(.lift)
            }
        }
        .padding(.vertical, 4)
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
