import Foundation

/// Applies a ``CachePolicy`` around a fetch closure, so call sites describe
/// *what* they want loaded and *how fresh* it has to be, and never hand-roll
/// the read-cache / call-network / write-cache dance themselves.
///
/// The loader knows nothing about networking: the work is whatever the `fetch`
/// closure does. That keeps it usable against a `URLSession` client, a GraphQL
/// client, or a fake in tests, and keeps this file free of any dependency on
/// the app's API layer.
///
/// ### Usage
/// ```swift
/// let cache = try DiskCache(name: "api", defaultTTL: 3600)
/// let loader = CachedLoader(cache: cache)
///
/// // Instant on re-entry, refetched once the entry passes five minutes.
/// let profile = try await loader.load(key: "profile/\(userID)",
///                                     policy: .cacheFirst(ttl: 300)) {
///     try await api.fetchProfile(userID)
/// }
/// self.profile = profile.value
///
/// // Live when online, last-known-good when not.
/// let feed = try await loader.load(key: "feed",
///                                  policy: .networkFirstFallbackToCache) {
///     try await api.fetchFeed()
/// }
/// self.items = feed.value
/// self.showingOfflineBanner = feed.isStale
/// ```
///
/// ### Choosing a key
/// The key must identify the *request*, not the endpoint: fold in every
/// parameter that changes the response (user id, page, filter, locale). Two
/// different requests sharing a key will serve each other's data. Keys are
/// hashed before they touch the file system, so any string is safe — see
/// ``DiskCache``.
actor CachedLoader {

    private let cache: DiskCache

    /// Creates a loader over an existing cache.
    ///
    /// Share one loader (and one cache) per logical store rather than creating
    /// them per request, so entries accumulate somewhere the next screen can
    /// find them.
    init(cache: DiskCache) {
        self.cache = cache
    }

    /// Loads a value under `policy`, using `fetch` whenever the network is
    /// needed.
    ///
    /// Decision table:
    ///
    /// | Policy | Cache read | Network | On fetch failure |
    /// | --- | --- | --- | --- |
    /// | `.networkOnly` | never | always | throws |
    /// | `.cacheFirst(ttl)` | hit younger than `ttl` wins | only on miss/stale | throws |
    /// | `.cacheThenNetwork(ttl)` | any hit wins, flagged by `ttl` | background, always | ignored (kept cached value) |
    /// | `.networkFirstFallbackToCache` | only after a failure | always | stale cache hit, else rethrow |
    ///
    /// Two deliberate asymmetries:
    /// - A failure to **write** the cache is swallowed. The caller asked for
    ///   data and got it; a full disk should not turn a successful request into
    ///   a thrown error.
    /// - A failure to **read** the cache is treated as a miss, never surfaced.
    ///   That is ``DiskCache``'s contract and this type does not weaken it.
    ///
    /// - Parameters:
    ///   - key: Identifier for this request. See *Choosing a key* above.
    ///   - policy: How to weigh cached data against fresh data.
    ///   - fetch: Performs the network request. Called at most once per call,
    ///     except under ``CachePolicy/cacheThenNetwork(ttl:)`` where it may
    ///     also be called on a detached background task.
    /// - Returns: The value with its provenance, so the caller can distinguish
    ///   fresh from stale-but-usable.
    /// - Throws: Whatever `fetch` throws, when the policy has no cached value
    ///   to fall back on. Cancellation always propagates.
    func load<V: Codable & Sendable>(
        key: String,
        policy: CachePolicy,
        fetch: @escaping @Sendable () async throws -> V
    ) async throws -> Cached<V> {
        switch policy {

        case .networkOnly:
            // Neither reads nor writes: "network only" is also how a caller
            // says "do not put this response on disk".
            let value = try await fetch()
            return Cached(value: value)

        case .cacheFirst(let ttl):
            // The freshness window is evaluated here against `storedAt` rather
            // than relying solely on the TTL baked in at store time, so
            // shortening `ttl` in a new build invalidates existing entries
            // immediately instead of when they happen to expire.
            if let entry = try? await cache.loadEntry(V.self, for: key), entry.age < ttl {
                return Cached(value: entry.value, storedAt: entry.storedAt, isStale: false)
            }
            return try await fetchAndStore(key: key, ttl: ttl, fetch: fetch)

        case .cacheThenNetwork(let ttl):
            if let entry = try? await cache.loadEntry(V.self, for: key) {
                revalidate(key: key, ttl: ttl, fetch: fetch)
                return Cached(value: entry.value, storedAt: entry.storedAt, isStale: entry.age >= ttl)
            }
            // Nothing to serve immediately, so there is nothing to revalidate
            // behind: degrade to a plain fetch.
            return try await fetchAndStore(key: key, ttl: ttl, fetch: fetch)

        case .networkFirstFallbackToCache:
            do {
                return try await fetchAndStore(key: key, ttl: nil, fetch: fetch)
            } catch {
                // Cancellation is not a failure to route around. A cancelled
                // URLSession task throws `URLError.cancelled` rather than
                // `CancellationError`, so test the task, not the error type.
                if Task.isCancelled { throw error }

                guard let entry = try? await cache.loadEntry(V.self, for: key) else {
                    // Nothing cached: the caller gets the real reason the
                    // request failed, not a cache-shaped error hiding it.
                    throw error
                }
                return Cached(value: entry.value, storedAt: entry.storedAt, isStale: true)
            }
        }
    }

    // MARK: - Helpers

    /// Fetches, stores the result, and wraps it as a fresh value.
    private func fetchAndStore<V: Codable & Sendable>(
        key: String,
        ttl: TimeInterval?,
        fetch: @Sendable () async throws -> V
    ) async throws -> Cached<V> {
        let value = try await fetch()
        try? await cache.store(value, for: key, ttl: ttl)
        return Cached(value: value)
    }

    /// Refreshes `key` in the background without blocking the caller.
    ///
    /// Detached on purpose, and at `.utility`: this work outlives the request
    /// that triggered it (cancelling the screen that asked should not cancel
    /// the refresh it kicked off) and must not inherit a user-interactive
    /// priority for something nobody is waiting on.
    ///
    /// Errors are dropped. The caller has already been given a usable value and
    /// has no way to act on a failure it never asked about; the entry simply
    /// stays stale until the next attempt.
    private func revalidate<V: Codable & Sendable>(
        key: String,
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> V
    ) {
        let cache = self.cache
        Task.detached(priority: .utility) {
            guard let value = try? await fetch() else { return }
            try? await cache.store(value, for: key, ttl: ttl)
        }
    }
}
