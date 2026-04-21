import SwiftUI

struct AppRouter: View {
    @State private var sessionStore = ScriptSessionStore()

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

            NotesView()
                .tabItem { Label("Notes", systemImage: "note.text") }

            GlobalSearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environment(sessionStore)
    }
}
