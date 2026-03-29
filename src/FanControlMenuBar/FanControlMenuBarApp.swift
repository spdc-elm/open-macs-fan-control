import SwiftUI

@main
struct FanControlMenuBarApp: App {
    @StateObject private var store = MenuBarTelemetryStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            MenuBarExtraLabel(snapshot: store.snapshot)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}
