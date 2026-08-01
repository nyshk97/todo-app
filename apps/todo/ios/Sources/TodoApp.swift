import SwiftData
import SwiftUI

@main
struct TodoApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: CachedTodo.self, CachedDate.self, PendingOperation.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
    }
}
