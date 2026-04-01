import SwiftUI

@main
struct TodoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 380, height: 600)
    }
}
