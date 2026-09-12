import Foundation

/// How ``CachedLoader`` should combine the cache and the network for one load.
///
/// The policy belongs to the *call site*, not to the cache: the same endpoint
/// is often loaded under different policies — `.cacheFirst` when a list screen
/// appears, `.networkOnly` when the user pulls to refresh.
enum CachePolicy: Equatable, Sendable {

    /// Always fetch; never read from or write to the cache.
    ///
    /// Choose this for data that must be current (a checkout total, a one-time
    /// code) or that should not be persisted at all. Because it does not write,
    /// it is also the correct policy for responses containing sensitive data
    /// you do not want sitting on disk — a pull-to-refresh on a public feed is
    /// better served by ``cacheThenNetwork(ttl:)``, which does warm the cache.
    ///
    /// A thrown fetch error propagates. There is no fallback.
    case networkOnly

    /// Serve the cached value if it is younger than `ttl`; otherwise fetch,
    /// store, and return the fresh value.
    ///
    /// The default for data that changes slowly and is expensive to fetch —
    /// a user profile, a settings payload, a reference list. A hit costs no
    /// network at all, which is what makes a screen reappear instantly.
    ///
    /// This is *not* the offline policy: if the entry is older than `ttl` and
    /// the fetch fails, the error is thrown even though a stale entry exists.
    /// Use ``networkFirstFallbackToCache`` if you would rather show old data
    /// than an error.
    ///
    /// - Parameter ttl: Freshness window, evaluated against the entry's
    ///   `storedAt`, and also used as the TTL when the fresh value is stored.
    case cacheFirst(ttl: TimeInterval)

    /// Return the cached value immediately, and revalidate in the background.
    ///
    /// Stale-while-revalidate. The caller gets whatever is cached — flagged via
    /// ``Cached/isStale`` when it is older than `ttl` — so the UI paints with no
    /// spinner, while a background fetch refreshes the cache for next time. If
    /// nothing is cached, it behaves like a plain fetch.
    ///
    /// Choose this for screens the user opens constantly where "instant but a
    /// minute old" beats "correct after 800ms". The trade-off is explicit: the
    /// refreshed value is only visible on the *next* load, and the background
    /// fetch always runs, even on a fresh hit — that costs battery and data.
    ///
    /// - Parameter ttl: Age past which the returned value is marked stale, and
    ///   the TTL used when storing.
    case cacheThenNetwork(ttl: TimeInterval)

    /// Fetch; if the fetch fails, fall back to whatever is cached.
    ///
    /// **This is the policy that gives graceful offline behaviour.** On a good
    /// connection the user always sees live data. On a plane, in a lift, or
    /// during a backend outage they see the last known good data marked
    /// ``Cached/isStale``, which is the cue to show an "offline — showing saved
    /// results" banner rather than an error screen. The error is only thrown
    /// when there is genuinely nothing cached to show.
    ///
    /// Task cancellation is never swallowed: a cancelled load throws rather
    /// than quietly resolving to stale data.
    ///
    /// Entries are stored with the cache's `defaultTTL`, so give the
    /// ``DiskCache`` a generous one (or a non-positive one for no expiry) if
    /// you rely on this policy — the fallback can only serve entries the cache
    /// has not already expired.
    case networkFirstFallbackToCache
}
