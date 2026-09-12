import Foundation
import Observation

/// An observable façade over a single Keychain-backed API token.
///
/// Views observe ``hasToken`` to decide between a "sign in" screen and the real
/// UI; the networking layer takes ``tokenProvider()`` and never learns where the
/// token came from. The token value itself is only ever read on demand, through
/// ``read()`` — it is not held in memory as published state.
///
/// Create one instance and put it in the environment:
///
/// ```swift
/// @State private var tokens = TokenStore()
/// …
/// ContentView().environment(tokens)
/// ```
///
/// - Important: The token is never logged, printed, or included in any error
///   this type throws.
// `@MainActor` is load-bearing, not decoration: `hasToken` is observable
// state that SwiftUI reads during layout, and `read()` mutates it. Without
// isolation a call from a background context is a data race on that
// property, and Swift 5 language mode will not diagnose it.
//
// `tokenProvider()` is deliberately unaffected: it captures only the
// `Sendable` keychain value and key, never `self`, so the closure it
// returns stays callable from the `APIClient` actor.
@MainActor
@Observable
final class TokenStore {

    /// Whether a token is currently stored.
    ///
    /// This is a *cached* flag, refreshed on `init` and after every mutation,
    /// precisely so that a SwiftUI `body` can read it without touching the
    /// Keychain. Keychain access is a cross-process call; doing it during view
    /// evaluation would run it on every re-render, on the main thread.
    ///
    /// It answers "is there a token?", never "what is the token?" — for the
    /// value, call ``read()``.
    private(set) var hasToken: Bool

    /// The backing store. A `let` of a `Sendable` value type, so the
    /// `@Observable` macro leaves it alone and it can be captured by escaping
    /// closures without capturing `self`.
    private let keychain: KeychainStore

    /// The `kSecAttrAccount` key the token lives under.
    private let key: String

    /// Creates a token store.
    ///
    /// - Parameters:
    ///   - keychain: Where to persist the token. Inject a store with a
    ///     different `service` to isolate tests or previews from the real token.
    ///   - key: The account key within that service.
    init(
        keychain: KeychainStore = KeychainStore(service: "com.dansandoval.firstiosapp.tokens"),
        key: String = "github-token"
    ) {
        self.keychain = keychain
        self.key = key
        self.hasToken = keychain.contains(key)
    }

    /// Stores `token`, replacing any existing one, and refreshes ``hasToken``.
    ///
    /// Leading and trailing whitespace and newlines are stripped first: a token
    /// pasted from a browser, a terminal, or a password manager very often
    /// arrives with a trailing newline, which would otherwise be sent verbatim
    /// in an `Authorization` header and rejected by the server with a
    /// confusing 401.
    ///
    /// - Throws: ``KeychainError/invalidData`` if `token` is empty once trimmed,
    ///   or ``KeychainError/unexpectedStatus(_:)`` on a Keychain failure.
    func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeychainError.invalidData
        }
        try keychain.setString(trimmed, for: key)
        hasToken = true
    }

    /// Deletes the stored token and refreshes ``hasToken``.
    ///
    /// Safe to call when no token is stored.
    ///
    /// - Throws: ``KeychainError/unexpectedStatus(_:)`` on a Keychain failure.
    func clear() throws {
        try keychain.remove(key)
        hasToken = false
    }

    /// Reads the current token.
    ///
    /// This hits the Keychain on every call — ``hasToken`` is a cache of
    /// *existence* and is never the source of truth for the value. Do not call
    /// this from a view's `body`.
    ///
    /// - Returns: The stored token, or `nil` if there is none.
    /// - Throws: ``KeychainError`` if the Keychain read fails or the stored
    ///   bytes are not valid UTF-8.
    func read() throws -> String? {
        let token = try keychain.string(for: key)
        // Keep the cached flag honest if the item changed behind our back —
        // another instance, an app extension, or a restore. Assign only on an
        // actual change so observers are not woken for a no-op.
        let exists = (token != nil)
        if hasToken != exists {
            hasToken = exists
        }
        return token
    }

    /// Builds a closure that yields the current token, for handing to the
    /// networking layer's `tokenProvider` parameter.
    ///
    /// ```swift
    /// let client = APIClient(tokenProvider: tokens.tokenProvider())
    /// ```
    ///
    /// The returned closure captures only the `KeychainStore` value and the key
    /// string — both `Sendable` — and deliberately **not** `self`. That keeps a
    /// long-lived client from retaining the store (no reference cycle) and keeps
    /// the closure free of any actor isolation it would inherit from a captured
    /// class instance, which is what lets it be `@Sendable`.
    ///
    /// A read failure is swallowed and reported as `nil`: an unreadable Keychain
    /// should degrade to an unauthenticated request, which fails with a clean
    /// 401 the UI already handles, rather than taking down the request path.
    ///
    /// - Returns: A `Sendable` async closure returning the token, or `nil`.
    func tokenProvider() -> @Sendable () async -> String? {
        let keychain = self.keychain
        let key = self.key
        return {
            do {
                return try keychain.string(for: key)
            } catch {
                // Intentionally silent, and intentionally not logging `error`
                // alongside anything token-shaped.
                return nil
            }
        }
    }
}
