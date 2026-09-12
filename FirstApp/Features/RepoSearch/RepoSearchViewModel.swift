import Foundation
import Observation

/// Drives the repository search screen. The client is injected rather than
/// constructed here so the screen can be tested against a stub transport, and so
/// the Keychain-backed token provider can be wired in once, at the app's root.
@Observable
@MainActor
final class RepoSearchViewModel {
    var query: String = ""
    private(set) var state: Loadable<[Repository]> = .idle
    private(set) var rateLimit: RateLimit?

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            return
        }

        state = .loading

        do {
            let response = try await client.send(GitHubAPI.searchRepositories(matching: trimmed))
            state = response.items.isEmpty ? .empty : .loaded(response.items)
        } catch let error as APIError {
            // Cancellation is the normal path here, not a failure: every keystroke
            // cancels the request in flight, and a replacement is already on its
            // way. Rendering an error for it would flash a failure at the user
            // mid-word, so it is swallowed and `.loading` is left standing.
            if error != .cancelled {
                state = .failed(error)
            }
        } catch is CancellationError {
            // Same reasoning, for a cancellation that surfaces before the client
            // has had a chance to translate it into `APIError.cancelled`.
        } catch {
            state = .failed(.transport(code: .unknown, description: error.localizedDescription))
        }

        rateLimit = await client.lastRateLimit
    }

    func retry() async {
        await search()
    }
}
