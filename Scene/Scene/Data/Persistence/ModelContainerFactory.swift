import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make() -> ModelContainer {
        let schema = Schema([
            ScriptDocument.self,
            ScriptNote.self,
            ScriptBookmark.self,
            ScriptTag.self,
            ScriptReadingSession.self
        ])

        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
