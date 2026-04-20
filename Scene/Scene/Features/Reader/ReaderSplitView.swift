import SwiftUI

struct ReaderSplitView: View {
    let document: ScriptDocument
    let initialJumpToPage: Int?
    let initialPracticeTurnSequenceIndex: Int?
    @StateObject private var vm = ReaderSplitViewModel()
    @State private var isShowingPractice = false
    @State private var hasAppliedInitialNavigation = false
    @State private var hasAutoOpenedPractice = false

    init(document: ScriptDocument, initialJumpToPage: Int? = nil, initialPracticeTurnSequenceIndex: Int? = nil) {
        self.document = document
        self.initialJumpToPage = initialJumpToPage
        self.initialPracticeTurnSequenceIndex = initialPracticeTurnSequenceIndex
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Scenes") {
                    if let parseResult = vm.parseResult, parseResult.scenes.isEmpty {
                        Text("No screenplay scene headings found in this PDF.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
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
                }

                Section("Practice") {
                    if let parseResult = vm.parseResult {
                        if parseResult.dialogueTurns.isEmpty {
                            Text("No dialogue turns detected yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                isShowingPractice = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Open Practice Mode")
                                    Text("\(parseResult.dialogueTurns.count) dialogue turns ready")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text("Build the index to unlock rehearsal mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Characters") {
                    if let parseResult = vm.parseResult, parseResult.characters.isEmpty {
                        Text("No screenplay character cues found in this PDF.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.parseResult?.characters ?? []) { c in
                            HStack {
                                Text(c.name)
                                Spacer()
                                if let turnCount = dialogueTurnCounts[c.name] {
                                    Text("\(turnCount) turns")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let p = c.firstPage {
                                    Text("p\(p + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if let parseResult = vm.parseResult, !parseResult.dialogueTurns.isEmpty {
                            Button("Practice") {
                                isShowingPractice = true
                            }
                        }

                        if vm.isParsing {
                            ProgressView()
                        } else {
                            Button("Rebuild Index") { Task { await vm.buildIndex(for: document) } }
                        }
                    }
                }
        }
        .task {
            if !hasAppliedInitialNavigation {
                vm.jumpToPage = initialJumpToPage
                hasAppliedInitialNavigation = true
            }

            await vm.buildIndex(for: document)
            autoOpenPracticeIfNeeded()
        }
        .onChange(of: vm.parseResult?.dialogueTurns.count ?? 0) { _, _ in
            autoOpenPracticeIfNeeded()
        }
        .sheet(isPresented: $isShowingPractice) {
            if let parseResult = vm.parseResult {
                PracticeSessionView(
                    document: document,
                    parseResult: parseResult,
                    initialFocusedTurnSequenceIndex: initialPracticeTurnSequenceIndex
                )
            }
        }
    }

    private var dialogueTurnCounts: [String: Int] {
        guard let parseResult = vm.parseResult else { return [:] }
        return parseResult.dialogueTurns.reduce(into: [:]) { counts, turn in
            counts[turn.characterName, default: 0] += 1
        }
    }

    private func autoOpenPracticeIfNeeded() {
        guard !hasAutoOpenedPractice,
              initialPracticeTurnSequenceIndex != nil,
              let parseResult = vm.parseResult,
              !parseResult.dialogueTurns.isEmpty else { return }

        hasAutoOpenedPractice = true
        isShowingPractice = true
    }
}
