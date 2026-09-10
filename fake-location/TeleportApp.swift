import SwiftUI

@main
struct TeleportApp: App {
    @State private var store = TeleportStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { store.begin() }
        }
    }
}
