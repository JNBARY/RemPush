import SwiftUI
import RemPushCore

@main
struct RemPushApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.refreshSharedSnapshotFromDisk()
            } else {
                viewModel.flushPendingSnapshotPersistence()
            }
        }
    }
}
