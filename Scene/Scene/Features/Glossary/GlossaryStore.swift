import Foundation

struct GlossaryTerm: Identifiable, Codable {
    var id: String { key }
    let key: String
    let title: String
    let description: String
}

@MainActor
final class GlossaryStore: ObservableObject {
    @Published private(set) var terms: [GlossaryTerm] = []

    func load() {
        guard let url = Bundle.main.url(forResource: "Glossary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([GlossaryTerm].self, from: data) else {
            terms = []
            return
        }
        terms = decoded.sorted { $0.title < $1.title }
    }
}
