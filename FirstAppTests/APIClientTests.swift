import Foundation
import XCTest
@testable import FirstApp

/// End-to-end behaviour of `APIClient` against a scripted transport: status
/// mapping, retry accounting, auth headers, and rate-limit bookkeeping.
/// No real network, no real clock beyond a millisecond backoff.
final class APIClientTests: XCTestCase {

    private let base = URL(string: "https://api.example.com")!
    private let endpoint = Endpoint<Fixture>(path: "/thing")

    /// Single-word keys, so the test does not depend on whatever key-decoding
    /// strategy `JSONDecoder.apiDefault` happens to apply.
    private struct Fixture: Codable, Equatable, Sendable {
        let id: Int
        let name: String
    }

    private static let okBody = #"{"id": 7, "name": "seven"}"#
    private static let okValue = Fixture(id: 7, name: "seven")

    /// Deliberately mixed-case. HTTP field names are case-insensitive by spec
    /// and GitHub sends these lowercase over HTTP/2 but capitalised over
    /// HTTP/1.1, so the parser must not depend on the casing it sees here.
    private static let rateLimitHeaders = [
        "X-RateLimit-Limit": "5000",
        "X-RateLimit-Remaining": "4987",
        "X-RateLimit-Reset": "1700000000"
    ]

    /// Jitter off and a millisecond base delay: this exercises the retry path
    /// without making the suite sit through a real exponential backoff.
    private let fastRetry = RetryPolicy(
        maxAttempts: 2,
        baseDelay: 0.001,
        maxDelay: 0.01,
        usesJitter: false
    )

    /// Retries are off by default here. Every test that asserts a single
    /// failure wants the client to give up after exactly one attempt, so the
    /// request count is unambiguous.
    private func makeClient(
        transport: MockTransport,
        retryPolicy: RetryPolicy = RetryPolicy.none,
        tokenProvider: (@Sendable () async -> String?)? = nil
    ) -> APIClient {
        APIClient(
            baseURL: base,
            transport: transport,
            retryPolicy: retryPolicy,
            tokenProvider: tokenProvider
        )
    }

    // MARK: - Success

    func testSuccessfulResponseDecodes() async throws {
        let transport = MockTransport([.json(Self.okBody)])
        let client = makeClient(transport: transport)

        let value = try await client.send(endpoint)

        XCTAssertEqual(value, Self.okValue)
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testRequestIsBuiltFromTheClientBaseURL() async throws {
        let transport = MockTransport([.json(Self.okBody)])
        let client = makeClient(transport: transport)

        _ = try await client.send(endpoint)

        XCTAssertEqual(transport.lastRequest?.url?.absoluteString, "https://api.example.com/thing")
    }

    // MARK: - Status mapping

    func testUnauthorizedStatusMapsToUnauthorized() async {
        let transport = MockTransport([.status(401)])
        let client = makeClient(transport: transport)

        let error = await apiError { try await client.send(self.endpoint) }

        // 401 gets its own case rather than .http(status: 401) so sign-out
        // handling never has to string-match a status code.
        XCTAssertEqual(error, .unauthorized)
    }

    func testNotFoundCarriesTheServerMessage() async {
        // GitHub's shape: the useful detail is in a top-level "message".
        let transport = MockTransport([.json(#"{"message": "Not Found"}"#, status: 404)])
        let client = makeClient(transport: transport)

        let error = await apiError { try await client.send(self.endpoint) }

        XCTAssertEqual(error, .http(status: 404, message: "Not Found"))
    }

    func testErrorBodyWithoutAMessageStillMapsToHTTP() async {
        let transport = MockTransport([.json(#"{"nope": true}"#, status: 404)])
        let client = makeClient(transport: transport)

        let error = await apiError { try await client.send(self.endpoint) }

        // An unparseable error body must not turn into a .decoding failure --
        // the status code is the real signal.
        guard case .http(let status, _)? = error else {
            return XCTFail("Expected .http, got \(String(describing: error))")
        }
        XCTAssertEqual(status, 404)
    }

    func testMalformedJSONMapsToDecoding() async {
        let transport = MockTransport([.json("{ this is not json")])
        let client = makeClient(transport: transport)

        let error = await apiError { try await client.send(self.endpoint) }

        // The `description` payload is implementation detail, so match the
        // case only.
        guard case .decoding? = error else {
            return XCTFail("Expected .decoding, got \(String(describing: error))")
        }
    }

    func testRateLimitedStatusMapsToRateLimited() async {
        let transport = MockTransport([.status(429, headers: ["Retry-After": "2"])])
        let client = makeClient(transport: transport)

        let error = await apiError { try await client.send(self.endpoint) }

        guard case .rateLimited(let retryAfter)? = error else {
            return XCTFail("Expected .rateLimited, got \(String(describing: error))")
        }
        XCTAssertEqual(retryAfter, 2, "Retry-After should be parsed out of the response headers")
    }

    // MARK: - Retry accounting

    func testServerErrorIsRetriedAndThenSucceeds() async throws {
        let transport = MockTransport([
            .status(500),
            .json(Self.okBody)
        ])
        let client = makeClient(transport: transport, retryPolicy: fastRetry)

        let value = try await client.send(endpoint)

        XCTAssertEqual(value, Self.okValue)
        XCTAssertEqual(
            transport.requestCount, 2,
            "maxAttempts: 2 means one original request plus exactly one retry"
        )
    }

    func testClientErrorIsNotRetried() async {
        let transport = MockTransport([.json(#"{"message": "Bad Request"}"#, status: 400)])
        let client = makeClient(transport: transport, retryPolicy: fastRetry)

        let error = await apiError { try await client.send(self.endpoint) }

        // Retrying a 400 cannot help: the request itself is what is wrong. The
        // request count is the assertion that matters -- if the client retried
        // anyway the mock's queue would be empty, the second call would throw
        // `queueExhausted`, and the reported error would be a transport
        // failure instead of the 400.
        XCTAssertEqual(error, .http(status: 400, message: "Bad Request"))
        XCTAssertEqual(transport.requestCount, 1, "4xx must not be retried")
    }

    func testRetriesStopAtMaxAttempts() async {
        let transport = MockTransport([.status(500), .status(500)])
        let client = makeClient(transport: transport, retryPolicy: fastRetry)

        let error = await apiError { try await client.send(self.endpoint) }

        guard case .http(let status, _)? = error else {
            return XCTFail("Expected .http, got \(String(describing: error))")
        }
        XCTAssertEqual(status, 500)
        XCTAssertEqual(transport.requestCount, 2, "It must not keep going past maxAttempts")
    }

    // MARK: - Authorization

    func testTokenProviderAddsABearerHeader() async throws {
        let transport = MockTransport([.json(Self.okBody)])
        let client = makeClient(transport: transport, tokenProvider: { "s3cret-token" })

        _ = try await client.send(endpoint)

        XCTAssertEqual(
            transport.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer s3cret-token"
        )
    }

    func testNilTokenAddsNoAuthorizationHeaderAtAll() async throws {
        let transport = MockTransport([.json(Self.okBody)])
        let client = makeClient(transport: transport, tokenProvider: { nil })

        _ = try await client.send(endpoint)

        // Not "Bearer " with an empty token, and not "Bearer null" -- the
        // header must be absent, or an API that treats a malformed token as a
        // hard 401 will break anonymous requests.
        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.allHTTPHeaderFields?["Authorization"])
    }

    func testEmptyTokenIsTreatedAsNoToken() async throws {
        let transport = MockTransport([.json(Self.okBody)])
        let client = makeClient(transport: transport, tokenProvider: { "" })

        _ = try await client.send(endpoint)

        // "Bearer " with nothing after it is a guaranteed 401 that hides the
        // real problem, which is that there is no token.
        XCTAssertNil(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testNoTokenProviderAddsNoAuthorizationHeader() async throws {
        let transport = MockTransport([.json(Self.okBody)])
        let client = makeClient(transport: transport)

        _ = try await client.send(endpoint)

        XCTAssertNil(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testEndpointHeadersSurviveAndOverrideClientDefaults() async throws {
        let transport = MockTransport([.json(Self.okBody)])
        let client = makeClient(transport: transport, tokenProvider: { "s3cret-token" })

        _ = try await client.send(
            Endpoint<Fixture>(
                path: "/thing",
                headers: ["X-Endpoint-Header": "kept", "Accept": "text/plain"]
            )
        )

        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Endpoint-Header"), "kept")
        // The client applies a default Accept; an endpoint that names its own
        // has to win, or an endpoint serving a non-JSON body can never say so.
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/plain")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret-token")
    }

    func testEndpointCanOptOutOfTheInjectedToken() async throws {
        let transport = MockTransport([.json(Self.okBody)])
        let client = makeClient(transport: transport, tokenProvider: { "s3cret-token" })

        _ = try await client.send(
            Endpoint<Fixture>(path: "/thing", headers: ["Authorization": "Basic abc123"])
        )

        // An endpoint that needs a different scheme must not have its header
        // overwritten by the bearer token.
        XCTAssertEqual(
            transport.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Basic abc123"
        )
    }

    // MARK: - Rate limit bookkeeping

    func testRateLimitIsNilBeforeAnyRequest() async {
        let client = makeClient(transport: MockTransport())

        let rateLimit = await client.lastRateLimit

        XCTAssertNil(rateLimit)
    }

    func testResponseRateLimitHeadersPopulateLastRateLimit() async throws {
        let resetsAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockTransport([.json(Self.okBody, headers: Self.rateLimitHeaders)])
        let client = makeClient(transport: transport)

        _ = try await client.send(endpoint)

        // Note: HTTPURLResponse may canonicalise header capitalisation, so
        // RateLimit's header lookup has to be case-insensitive.
        let rateLimit = try XCTUnwrap(
            await client.lastRateLimit,
            "Rate-limit headers on the response should have been captured"
        )
        XCTAssertEqual(rateLimit.limit, 5000)
        XCTAssertEqual(rateLimit.remaining, 4987)
        XCTAssertEqual(rateLimit.resetsAt, resetsAt)
    }

    func testHeaderlessResponseNeverPopulatesLastRateLimit() async throws {
        let transport = MockTransport([.json(Self.okBody)])
        let client = makeClient(transport: transport)

        _ = try await client.send(endpoint)

        // Nothing to parse, so nothing recorded. A partial snapshot would be
        // worse than none: a caller reading `remaining` off a defaulted value
        // would throttle against fiction.
        let rateLimit = await client.lastRateLimit
        XCTAssertNil(rateLimit)
    }

    func testHeaderlessResponsePreservesAnEarlierRateLimit() async throws {
        let transport = MockTransport([
            .json(Self.okBody, headers: Self.rateLimitHeaders),
            .json(Self.okBody)
        ])
        let client = makeClient(transport: transport)

        _ = try await client.send(endpoint)
        _ = try await client.send(endpoint)

        // Preserved, not cleared. One unrelated header-less endpoint must not
        // make the whole budget read as unknown.
        let rateLimit = try XCTUnwrap(await client.lastRateLimit)
        XCTAssertEqual(rateLimit.remaining, 4987)
    }

    func testAFailedResponseStillRefreshesTheRateLimit() async {
        let transport = MockTransport([
            .json(#"{"message": "Not Found"}"#, status: 404, headers: [
                "X-RateLimit-Limit": "60",
                "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": "1700000000"
            ])
        ])
        let client = makeClient(transport: transport)

        _ = await apiError { try await client.send(self.endpoint) }

        // The 404 spent budget too. Recording it only on success would let a
        // caller keep hammering a quota it has already exhausted.
        let rateLimit = await client.lastRateLimit
        XCTAssertEqual(rateLimit?.remaining, 0)
        XCTAssertEqual(rateLimit?.limit, 60)
    }

    // MARK: - Helpers

    /// Runs `body`, expecting it to throw an `APIError`, and hands the error
    /// back. Fails the test (at the caller's line) if it returns a value or
    /// throws something else -- which is what happens when the mock's queue
    /// runs dry because of an unexpected retry.
    private func apiError<R>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> R
    ) async -> APIError? {
        do {
            _ = try await body()
            XCTFail("Expected the call to throw, but it returned a value.", file: file, line: line)
            return nil
        } catch let error as APIError {
            return error
        } catch {
            XCTFail("Expected an APIError, got \(error).", file: file, line: line)
            return nil
        }
    }
}
