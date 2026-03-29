import SwiftUI

@main
struct FanControlMenuBarApp: App {
    @StateObject private var store = MenuBarTelemetryStore()
    @StateObject private var controllerStore = MenuBarControllerStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store, controllerStore: controllerStore)
        } label: {
            MenuBarExtraLabel(
                snapshot: store.snapshot,
                controllerStatus: controllerStore.status,
                controllerErrorMessage: controllerStore.errorMessage
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}
