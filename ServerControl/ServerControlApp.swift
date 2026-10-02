import SwiftUI

@main
struct ServerControlApp: App {
    init() { _ = NotificationManager.shared }
    var body: some Scene {
        WindowGroup { AppRootView() }
    }
}
