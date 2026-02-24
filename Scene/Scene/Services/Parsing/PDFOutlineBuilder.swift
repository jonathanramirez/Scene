import Foundation

enum PDFOutlineBuilder {
    static func buildScenes(from pages: [(pageIndex: Int, text: String)]) -> [ScriptScene] {
        var scenes: [ScriptScene] = []
        var idx = 0

        for (pageIndex, text) in pages {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for line in lines {
                if ScriptFormatHeuristics.isSceneHeading(line) {
                    idx += 1
                    scenes.append(.init(index: idx,
                                        heading: line.trimmingCharacters(in: .whitespacesAndNewlines),
                                        startPage: pageIndex,
                                        endPage: nil))
                }
            }
        }

        // Fill endPage
        if !scenes.isEmpty {
            for i in scenes.indices {
                let nextStart = (i + 1 < scenes.count) ? scenes[i + 1].startPage : nil
                scenes[i].endPage = nextStart.map { max($0 - 1, scenes[i].startPage) }
            }
        }

        return scenes
    }
}
