import SwiftUI
import SwiftData

@main
struct SceneApp: App {
    var body: some Scene {
        WindowGroup {
            AppRouter()
        }
        .modelContainer(ModelContainerFactory.make())
    }
}
