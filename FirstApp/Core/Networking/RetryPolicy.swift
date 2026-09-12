import Foundation

/// How many times, and how patiently, ``APIClient`` retries a failed request.
///
/// The policy decides *whether* and *how long*; the client does the waiting.
/// Keeping the arithmetic here means it can be unit-tested without a network.
struct RetryPolicy: Sendable {

    /// Total attempts including the first one. `1` disables retrying.
    var maxAttempts: Int

    /// Delay before the second attempt, in seconds. Each further attempt
    /// doubles it.
    var baseDelay: TimeInterval

    /// Ceiling on the computed backoff, in seconds. Without it the doubling
    /// runs away after a handful of attempts.
    var maxDelay: TimeInterval

    /// Whether ``delay(forAttempt:)`` randomises its result. See that method
    /// for why you normally want this on.
    var usesJitter: Bool

    /// Creates a policy.
    ///
    /// - Parameters:
    ///   - maxAttempts: Total attempts including the first. Values below 1 are
    ///     clamped to 1 — a policy that permits zero attempts would mean a
    ///     request that is never sent.
    ///   - baseDelay: Seconds before the second attempt. Negatives clamp to 0.
    ///   - maxDelay: Upper bound on the computed backoff, never below `baseDelay`.
    ///   - usesJitter: Whether to apply full jitter. Defaults to `true`.
    init(maxAttempts: Int, baseDelay: TimeInterval, maxDelay: TimeInterval, usesJitter: Bool = true) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(self.baseDelay, maxDelay)
        self.usesJitter = usesJitter
    }

    /// Three attempts, 0.5s base, 8s ceiling, jitter on. A reasonable default
    /// for user-facing reads: roughly 0.5s then 1s of extra waiting at worst,
    /// which stays under the threshold where a person abandons the screen.
    static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 0.5,
        maxDelay: 8,
        usesJitter: true
    )

    /// One attempt, no retrying. Use for non-idempotent writes, or in tests
    /// that assert on the first failure.
    ///
    /// - Note: `RetryPolicy.none` collides with `Optional.none` at a call site
    ///   typed `RetryPolicy?`, where `.none` resolves to the optional. Spell it
    ///   `RetryPolicy.none` in that position.
    static let none = RetryPolicy(
        maxAttempts: 1,
        baseDelay: 0,
        maxDelay: 0,
        usesJitter: false
    )

    /// Whether to make another attempt after `error` on attempt number
    /// `attempt`.
    ///
    /// - Parameters:
    ///   - error: The failure that just occurred.
    ///   - attempt: The 1-based number of the attempt that produced `error`.
    /// - Returns: `true` only when the budget allows another attempt *and* the
    ///   error is one that could resolve itself. Classification lives on
    ///   ``APIError/isRetryable`` so both types cannot drift apart.
    func shouldRetry(_ error: APIError, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        return error.isRetryable
    }

    /// How long to wait before attempt number `attempt + 1`.
    ///
    /// Exponential backoff: `baseDelay * 2^(attempt - 1)`, capped at
    /// ``maxDelay``.
    ///
    /// With ``usesJitter`` on, the result is then drawn uniformly from
    /// `0...computed` — "full jitter". The point is not to be polite to one
    /// server but to break up *correlated* retries: when an outage fails a
    /// thousand clients at the same instant, an unjittered backoff makes all
    /// thousand come back at the same instant too, and keep doing so in
    /// lockstep, hammering the service exactly as it tries to recover.
    /// Spreading each client randomly across the window flattens that spike.
    ///
    /// With ``usesJitter`` off the result is fully deterministic, which is what
    /// tests assert against.
    ///
    /// - Parameter attempt: The 1-based number of the attempt that just failed.
    /// - Returns: Seconds to wait. Never negative.
    func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let exponential = baseDelay * pow(2, Double(exponent))
        // `pow` can overflow to .infinity with a large exponent; min() with a
        // finite cap collapses that back to maxDelay rather than propagating it.
        let capped = min(exponential, maxDelay)
        let bounded = max(0, capped)

        guard usesJitter, bounded > 0 else { return bounded }
        return Double.random(in: 0...bounded)
    }
}
