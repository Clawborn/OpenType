import SwiftUI

@main
struct OpenTypeiOSApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .tint(.blue)
        }
    }
}
