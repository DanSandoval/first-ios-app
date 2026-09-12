import Foundation

/// Endpoint definitions for the GitHub REST API. A namespace, not a type to be
/// instantiated: the `APIClient` holds the state, these are just descriptions.
enum GitHubAPI {
    /// The one force-unwrap the codebase allows: a compile-time string constant
    /// that cannot fail to parse, checked once by the first line of any test run.
    static let baseURL = URL(string: "https://api.github.com")!

    /// Repository search, most-starred first.
    ///
    /// - Parameters:
    ///   - query: the raw user text; it is sent as-is, and URL encoding is the
    ///     client's job via `URLComponents`.
    ///   - perPage: page size. GitHub caps search at 100.
    static func searchRepositories(matching query: String, perPage: Int = 25) -> Endpoint<RepositorySearchResponse> {
        Endpoint(
            path: "/search/repositories",
            method: .get,
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "sort", value: "stars"),
                URLQueryItem(name: "order", value: "desc")
            ],
            headers: ["Accept": "application/vnd.github+json"]
        )
    }
}
