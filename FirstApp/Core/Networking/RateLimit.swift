import Foundation

/// A snapshot of the caller's rate-limit budget, parsed from response headers.
///
/// GitHub reports the budget on *every* response, so ``APIClient`` keeps the
/// latest one in ``APIClient/lastRateLimit``. A UI can show "12 requests left"
/// or pre-emptively stop polling without spending a request to find out.
struct RateLimit: Sendable, Equatable {

    /// Total requests allowed in the current window.
    let limit: Int

    /// Requests still available in the current window.
    let remaining: Int

    /// When the window resets and ``remaining`` returns to ``limit``.
    let resetsAt: Date

    /// Parses the `x-ratelimit-*` family out of a response's header dictionary.
    ///
    /// Header lookup is case-insensitive. HTTP field names are case-insensitive
    /// by spec, and `HTTPURLResponse.allHeaderFields` preserves whatever casing
    /// the server sent — GitHub sends lowercase over HTTP/2 and capitalised
    /// over HTTP/1.1, so a literal subscript works only by luck.
    ///
    /// - Parameter headers: Typically `HTTPURLResponse.allHeaderFields`.
    /// - Returns: `nil` if any of the three headers is missing or unparseable.
    ///   A partial snapshot would be worse than none, since a caller reading
    ///   `remaining` from a defaulted value would throttle against fiction.
    init?(headers: [AnyHashable: Any]) {
        guard let limit = RateLimit.integer(forHeader: "x-ratelimit-limit", in: headers),
              let remaining = RateLimit.integer(forHeader: "x-ratelimit-remaining", in: headers),
              let reset = RateLimit.double(forHeader: "x-ratelimit-reset", in: headers) else {
            return nil
        }

        self.limit = limit
        self.remaining = remaining
        // `x-ratelimit-reset` is epoch seconds, not a delta and not milliseconds.
        self.resetsAt = Date(timeIntervalSince1970: reset)
    }

    /// Case-insensitive header lookup returning the raw string value.
    ///
    /// Values arrive as `String` in practice, but `allHeaderFields` is typed
    /// `[AnyHashable: Any]`, so `NSNumber` is accepted too rather than being
    /// dropped on a technicality.
    private static func string(forHeader name: String, in headers: [AnyHashable: Any]) -> String? {
        for (key, value) in headers {
            guard let key = key as? String,
                  key.caseInsensitiveCompare(name) == .orderedSame else {
                continue
            }

            if let value = value as? String {
                return value
            }
            if let value = value as? NSNumber {
                return value.stringValue
            }
            return nil
        }
        return nil
    }

    private static func integer(forHeader name: String, in headers: [AnyHashable: Any]) -> Int? {
        guard let raw = string(forHeader: name, in: headers) else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    private static func double(forHeader name: String, in headers: [AnyHashable: Any]) -> Double? {
        guard let raw = string(forHeader: name, in: headers) else { return nil }
        return Double(raw.trimmingCharacters(in: .whitespaces))
    }
}
