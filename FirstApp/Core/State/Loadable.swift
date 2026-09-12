import Foundation

/// The state of a single piece of asynchronously loaded content.
///
/// Drive a screen from one `Loadable` property rather than from a scattering of
/// `isLoading` / `errorMessage` / `items` flags: the cases are mutually
/// exclusive by construction, so the "spinner still showing behind an error"
/// class of bug cannot be expressed.
///
/// ```swift
/// switch state {
/// case .idle, .loading: LoadingStateView()
/// case .loaded(let repos): RepoList(repos)
/// case .empty: EmptyStateView(title: "No results", …)
/// case .failed(let error): ErrorStateView(error: error) { await reload() }
/// }
/// ```
///
/// - Note: ``empty`` is deliberately a separate case from `.loaded([])`. A
///   search that ran and matched nothing needs different UI — "No results for
///   'xyz'", with the query still on screen — from a list that simply has no
///   content yet, and from one that has not been run at all (``idle``).
///   Collapsing the two forces the view to re-derive that distinction from a
///   count, which is exactly the information the enum is supposed to carry.
enum Loadable<Value: Sendable>: Sendable {

    /// Nothing has been requested yet. The initial state.
    case idle

    /// A request is in flight.
    case loading

    /// A request succeeded and produced content.
    case loaded(Value)

    /// A request succeeded but produced no content (no matches, empty feed).
    case empty

    /// A request failed.
    case failed(APIError)
}

extension Loadable {

    /// The loaded value, or `nil` in every other state.
    ///
    /// Note that ``empty`` yields `nil`: there is no value, by definition.
    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    /// Whether a request is currently in flight.
    ///
    /// ``idle`` is *not* loading — use it to decide whether to kick off the
    /// first request in `.task { }`.
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// The failure, or `nil` if the state is not ``failed(_:)``.
    var error: APIError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

/// Equatable whenever the wrapped value is, so SwiftUI can diff the state and
/// tests can assert on it directly.
extension Loadable: Equatable where Value: Equatable {}
