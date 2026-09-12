import SwiftUI

/// Tab-based container. Each tab owns its own `NavigationStack`, which is the
/// standard iOS pattern: navigation state is per-tab, not global.
struct RootView: View {
    // Built once, in `init`, and held in @State so they survive every redraw of
    // this view. A client rebuilt per render would lose its rate-limit state and
    // its connection reuse on each pass; the search view model owns the one
    // instance, and the token store is shared with the settings sheet.
    @State private var tokenStore: TokenStore
    @State private var searchViewModel: RepoSearchViewModel

    init() {
        let tokenStore = TokenStore()
        let client = APIClient(
            baseURL: GitHubAPI.baseURL,
            tokenProvider: tokenStore.tokenProvider()
        )

        _tokenStore = State(initialValue: tokenStore)
        _searchViewModel = State(initialValue: RepoSearchViewModel(client: client))
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            ItemListView()
                .tabItem { Label("List", systemImage: "list.bullet") }

            RepoSearchView(viewModel: searchViewModel, tokenStore: tokenStore)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            DeviceView()
                .tabItem { Label("Device", systemImage: "iphone") }
        }
    }
}

#Preview {
    RootView()
}
