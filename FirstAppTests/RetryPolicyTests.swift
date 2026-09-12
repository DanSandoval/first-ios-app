import Foundation
import XCTest
@testable import FirstApp

/// Backoff arithmetic and the retry/don't-retry decision, in isolation from
/// the client. Jitter is off everywhere here so the delays are exact numbers
/// rather than a range.
final class RetryPolicyTests: XCTestCase {

    private let policy = RetryPolicy(
        maxAttempts: 4,
        baseDelay: 0.5,
        maxDelay: 2.0,
        usesJitter: false
    )

    // MARK: - Backoff

    func testDelayDoublesPerAttempt() {
        // `attempt` is 1-based: attempt 1 is the first try, and the returned
        // value is how long to wait *after* it fails.
        XCTAssertEqual(policy.delay(forAttempt: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 2), 1.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 3), 2.0, accuracy: 0.0001)
    }

    func testDelayIsClampedToMaxDelay() {
        // Attempt 4 would be 0.5 * 2^3 = 4.0 without the clamp.
        XCTAssertEqual(policy.delay(forAttempt: 4), 2.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 10), 2.0, accuracy: 0.0001)
    }

    func testDelayNeverGoesNegativeOrRunsAway() {
        for attempt in 1...12 {
            let delay = policy.delay(forAttempt: attempt)
            XCTAssertGreaterThanOrEqual(delay, 0, "attempt \(attempt)")
            XCTAssertLessThanOrEqual(delay, policy.maxDelay, "attempt \(attempt)")
        }
    }

    // MARK: - shouldRetry

    func testTransientFailuresAreRetried() {
        let retryable: [APIError] = [
            .http(status: 500, message: nil),
            .http(status: 502, message: "bad gateway"),
            .http(status: 503, message: nil),
            .transport(code: .timedOut, description: "timed out"),
            .transport(code: .networkConnectionLost, description: "connection lost"),
            .rateLimited(retryAfter: nil),
            .rateLimited(retryAfter: 1)
        ]

        for error in retryable {
            XCTAssertTrue(error.isRetryable, "\(error) should report isRetryable")
            XCTAssertTrue(policy.shouldRetry(error, attempt: 1), "\(error) should be retried")
        }
    }

    func testPermanentFailuresAreNotRetried() {
        let permanent: [APIError] = [
            // Cancellation is a decision, not a fault -- retrying it would
            // resurrect work the caller just tore down.
            .cancelled,
            .unauthorized,
            .decoding(description: "keyNotFound"),
            .invalidURL,
            .http(status: 400, message: nil),
            .http(status: 404, message: "missing"),
            .http(status: 422, message: "unprocessable")
        ]

        for error in permanent {
            XCTAssertFalse(error.isRetryable, "\(error) should not report isRetryable")
            XCTAssertFalse(policy.shouldRetry(error, attempt: 1), "\(error) should not be retried")
        }
    }

    func testRateLimitedIsRetryableEvenThoughItIsA4xx() {
        // 429 is the one 4xx worth retrying: the request is fine, the timing
        // is not. It gets its own case precisely so the policy does not have
        // to carve an exception out of the "never retry 4xx" rule.
        XCTAssertTrue(policy.shouldRetry(.rateLimited(retryAfter: nil), attempt: 1))
    }

    // MARK: - Attempt budget

    func testRetryingStopsOnceTheAttemptBudgetIsSpent() {
        let error = APIError.http(status: 500, message: nil)

        XCTAssertTrue(policy.shouldRetry(error, attempt: 1))
        XCTAssertTrue(policy.shouldRetry(error, attempt: 3))
        XCTAssertFalse(
            policy.shouldRetry(error, attempt: 4),
            "Attempt 4 of maxAttempts 4 is the last one; there is nothing left to retry"
        )
        XCTAssertFalse(policy.shouldRetry(error, attempt: 5))
        XCTAssertFalse(policy.shouldRetry(error, attempt: 99))
    }

    // MARK: - The two shipped policies

    func testNoneNeverRetries() {
        let none = RetryPolicy.none

        XCTAssertEqual(none.maxAttempts, 1)
        XCTAssertFalse(none.shouldRetry(.http(status: 500, message: nil), attempt: 1))
        XCTAssertFalse(none.shouldRetry(.transport(code: .timedOut, description: "x"), attempt: 1))
    }

    func testDefaultRetriesTransientFailuresAtLeastOnce() {
        let standard = RetryPolicy.default

        XCTAssertGreaterThan(standard.maxAttempts, 1)
        XCTAssertTrue(standard.shouldRetry(.http(status: 500, message: nil), attempt: 1))
        XCTAssertFalse(standard.shouldRetry(.unauthorized, attempt: 1))
        XCTAssertFalse(
            standard.shouldRetry(.http(status: 500, message: nil), attempt: standard.maxAttempts),
            "The last attempt must not schedule another one"
        )
    }
}
