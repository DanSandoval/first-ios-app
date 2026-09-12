import SwiftUI

/// Search-as-you-type over GitHub repositories, built on the shared `APIClient`.
struct RepoSearchView: View {
    @Bindable var viewModel: RepoSearchViewModel
    let tokenStore: TokenStore

    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .searchable(text: $viewModel.query, prompt: "Repositories")
                .navigationDestination(for: Repository.self) { repository in
                    RepositoryDetailView(repository: repository)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: tokenStore.hasToken ? "key.fill" : "person.badge.key.fill")
                        }
                        .accessibilityLabel("API token settings")
                        .accessibilityValue(tokenStore.hasToken ? "Token stored" : "No token stored")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let rateLimit = viewModel.rateLimit {
                        RateLimitBar(rateLimit: rateLimit)
                    }
                }
                .sheet(isPresented: $isShowingSettings) {
                    APISettingsView(tokenStore: tokenStore)
                }
                // The debounce. `.task(id:)` cancels and restarts this task every
                // time the query changes, so the sleep below is what absorbs a run
                // of keystrokes: if another character arrives inside 350 ms the
                // task is cancelled mid-sleep, the guard sees it, and no request is
                // ever made. Cancellation is the mechanism, not an error path.
                .task(id: viewModel.query) {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await viewModel.search()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            EmptyStateView(
                title: "Search GitHub",
                message: "Start typing a repository name, a topic, or an owner.",
                systemImage: "magnifyingglass"
            )

        case .loading:
            LoadingStateView(message: "Searching GitHub…")

        case .empty:
            EmptyStateView(
                title: "No matches",
                message: "Nothing on GitHub matched that search. Try a broader term.",
                systemImage: "questionmark.folder"
            )

        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await viewModel.retry() }
            }

        case .loaded(let repositories):
            List(repositories) { repository in
                NavigationLink(value: repository) {
                    RepositoryRow(repository: repository)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Row

private struct RepositoryRow: View {
    let repository: Repository

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(repository.fullName)
                .font(.headline)

            if let description = repository.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Label(
                    repository.stargazersCount.formatted(.number.notation(.compactName)),
                    systemImage: "star.fill"
                )
                .accessibilityLabel("\(repository.stargazersCount) stars")

                if let language = repository.language {
                    Text(language)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

private struct RepositoryDetailView: View {
    let repository: Repository

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                owner

                if let description = repository.description, !description.isEmpty {
                    Card("About", systemImage: "text.alignleft") {
                        Text(description)
                            .font(.body)
                    }
                }

                Card("Popularity", systemImage: "chart.bar.fill") {
                    VStack(spacing: 10) {
                        statRow("Stars", repository.stargazersCount)
                        statRow("Forks", repository.forksCount)

                        if let language = repository.language {
                            HStack {
                                Text("Language")
                                Spacer()
                                Text(language)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.body)
                }

                if let url = URL(string: repository.htmlURL) {
                    Link(destination: url) {
                        Label("Open on GitHub", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var owner: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: repository.owner.avatarURL)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(.tertiarySystemFill)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(repository.fullName)
                    .font(.headline)
                Text(repository.owner.login)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.formatted(.number))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rate limit

private struct RateLimitBar: View {
    let rateLimit: RateLimit

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text("\(rateLimit.remaining)/\(rateLimit.limit) requests left")
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rateLimit.remaining) of \(rateLimit.limit) API requests remaining")
    }
}

#Preview("Search") {
    RepoSearchView(
        viewModel: RepoSearchViewModel(client: APIClient(baseURL: GitHubAPI.baseURL)),
        tokenStore: TokenStore()
    )
}

#Preview("Detail") {
    NavigationStack {
        RepositoryDetailView(repository: .previewSwift)
    }
}
