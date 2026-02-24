import SwiftUI

struct ReaderSplitView: View {
    let document: ScriptDocument
    @StateObject private var vm = ReaderSplitViewModel()

    var body: some View {
        NavigationSplitView {
            List {
                Section("Scenes") {
                    ForEach(vm.parseResult?.scenes ?? []) { scene in
                        Button {
                            vm.jumpToPage = scene.startPage
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("#\(scene.index) \(scene.heading)")
                                    .lineLimit(2)
                                Text("Page \(scene.startPage + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Characters") {
                    ForEach(vm.parseResult?.characters ?? []) { c in
                        HStack {
                            Text(c.name)
                            Spacer()
                            if let p = c.firstPage {
                                Text("p\(p + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(document.title)
        } detail: {
            ReaderView(document: document, jumpToPage: $vm.jumpToPage)
                .navigationTitle(document.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if vm.isParsing {
                            ProgressView()
                        } else {
                            Button("Rebuild Index") { Task { await vm.buildIndex(for: document) } }
                        }
                    }
                }
        }
        .task { await vm.buildIndex(for: document) }
    }
}
