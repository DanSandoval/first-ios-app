import SwiftUI

@main
struct FirstApp: App {
    /// Bumped once per process launch so `DeviceView` can prove that
    /// `@AppStorage` (UserDefaults) really does survive a force-quit.
    init() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: StorageKey.launchCount) + 1,
                     forKey: StorageKey.launchCount)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

enum StorageKey {
    static let launchCount = "launchCount"
    static let nickname = "nickname"
}
