import Foundation

/// A loaded value plus enough provenance for the UI to be honest about it.
///
/// The point of this wrapper is that "I have data" and "I have *current* data"
/// are different states, and collapsing them is how an app ends up silently
/// showing yesterday's prices. A view holding a `Cached<Value>` can render the
/// content and, when ``isStale`` is `true`, add the affordance that says so —
/// an "offline, showing saved results" banner, a dimmed timestamp, a retry
/// button — instead of pretending the data is live.
///
/// ```swift
/// let result = try await loader.load(key: "feed", policy: .networkFirstFallbackToCache) {
///     try await api.fetchFeed()
/// }
/// feed = result.value
/// offlineBanner = result.isStale ? "Showing saved results" : nil
/// ```
struct Cached<Value: Sendable>: Sendable {

    /// The loaded value. Always present — a `Cached` is only produced on
    /// success, whether that success came from the network or from disk.
    let value: Value

    /// When this value was obtained. For a fresh fetch, roughly "now"; for a
    /// cache hit, when the entry was written. Drives "updated 4 minutes ago".
    let storedAt: Date

    /// `true` when the value came from the cache and is past the freshness
    /// window the policy asked for, or was served as an offline fallback after
    /// a failed fetch. It means "usable, but do not present this as live".
    let isStale: Bool

    /// Creates a result wrapper.
    ///
    /// - Parameters:
    ///   - value: The loaded value.
    ///   - storedAt: When the value was obtained. Defaults to now, which is
    ///     what a caller constructing a fresh result wants.
    ///   - isStale: Whether the value should be presented as potentially
    ///     out of date. Defaults to `false`.
    init(value: Value, storedAt: Date = Date(), isStale: Bool = false) {
        self.value = value
        self.storedAt = storedAt
        self.isStale = isStale
    }

    /// How long ago ``storedAt`` was — convenient for a relative timestamp or
    /// for deciding whether to show the staleness affordance at all.
    var age: TimeInterval { Date().timeIntervalSince(storedAt) }

    /// Returns a new result carrying `transform(value)` with the same
    /// provenance. Useful for mapping a DTO to a view model without losing
    /// the freshness information along the way.
    func map<T: Sendable>(_ transform: (Value) throws -> T) rethrows -> Cached<T> {
        Cached<T>(value: try transform(value), storedAt: storedAt, isStale: isStale)
    }
}

extension Cached: Equatable where Value: Equatable {}
