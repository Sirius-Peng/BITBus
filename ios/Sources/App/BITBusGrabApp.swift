import SwiftUI

@main
struct BITBusGrabApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(appModel.taskManager)
        }
    }
}
