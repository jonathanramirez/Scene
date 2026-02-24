import SwiftUI

struct AppRouter: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }

            NotesView()
                .tabItem { Label("Notes", systemImage: "note.text") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
