import SwiftUI

@main
struct ClearApp: App {
    var body: some Scene {
        WindowGroup {
            ClearRootView()
        }
        .defaultSize(width: 1_040, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
