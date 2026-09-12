import SwiftUI

/// Tab-based container. Each tab owns its own `NavigationStack`, which is the
/// standard iOS pattern: navigation state is per-tab, not global.
struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            ItemListView()
                .tabItem { Label("List", systemImage: "list.bullet") }

            DeviceView()
                .tabItem { Label("Device", systemImage: "iphone") }
        }
    }
}

#Preview {
    RootView()
}
