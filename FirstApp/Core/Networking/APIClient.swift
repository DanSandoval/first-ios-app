import Foundation

/// Sends ``Endpoint`` values and decodes their responses.
///
/// An `actor` because ``lastRateLimit`` is mutable state that concurrent
/// requests both write, and because the UI calls into it from arbitrary tasks.
/// Serialising through the actor removes the data race without a lock.
///
/// Everything variable about the client is injected, so the same type serves
/// production and tests:
///
/// ```swift
/// let client = APIClient(baseURL: URL(string: "https://api.github.com")!)
/// let user = try await client.send(Endpoint<User>(path: "users/octocat"))
/// ```
///
/// - Important: The client never logs, prints, or embeds the bearer token in
///   any error, description, or debug output. ``APIError`` carries only status
///   codes, `URLError` codes, and server-supplied messages — never a request
///   header. Anything added here must preserve that: a token that reaches a log
///   file or a crash report is a leaked credential.
actor APIClient {

    private let baseURL: URL
    private let transport: HTTPTransport
    private let retryPolicy: RetryPolicy
    private let decoder: JSONDecoder
    private let tokenProvider: (@Sendable () async -> String?)?

    /// The rate-limit budget reported by the most recent response, or `nil` if
    /// no response has carried parseable `x-ratelimit-*` headers yet.
    ///
    /// Updated on every response, success or failure. A response without those
    /// headers leaves the previous snapshot in place rather than erasing it —
    /// an unrelated header-less endpoint should not make the budget look
    /// unknown.
    private(set) var lastRateLimit: RateLimit?

    /// Headers applied to every request unless the endpoint overrides them.
    private static let defaultHeaders: [String: String] = [
        "Accept": "application/vnd.github+json"
    ]

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - baseURL: API root, e.g. `https://api.github.com`. A path on the base
    ///     URL (`https://host/api/v3`) is preserved — see
    ///     ``Endpoint/urlRequest(baseURL:)``.
    ///   - transport: Network seam. Defaults to `URLSession.shared`; tests pass
    ///     a stub.
    ///   - retryPolicy: Retry behaviour. Defaults to ``RetryPolicy/default``.
    ///   - decoder: Decoder for 2xx bodies. Defaults to
    ///     ``Foundation/JSONDecoder/apiDefault``.
    ///   - tokenProvider: Asynchronously supplies the current bearer token, or
    ///     `nil` when unauthenticated.
    init(
        baseURL: URL,
        transport: HTTPTransport = URLSession.shared,
        retryPolicy: RetryPolicy = .default,
        decoder: JSONDecoder = .apiDefault,
        tokenProvider: (@Sendable () async -> String?)? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.decoder = decoder
        self.tokenProvider = tokenProvider
    }

    /// Sends an endpoint and decodes its response.
    ///
    /// Retries according to the client's ``RetryPolicy``, waiting between
    /// attempts. For a 429 the server's `Retry-After` wins over the computed
    /// backoff — it knows when the window actually reopens.
    ///
    /// - Parameter endpoint: The call to make. Its generic parameter fixes the
    ///   return type.
    /// - Returns: The decoded response body.
    /// - Throws: ``APIError``, and only ``APIError``.
    func send<R: Decodable & Sendable>(_ endpoint: Endpoint<R>) async throws -> R {
        let request = try await authorized(endpoint.urlRequest(baseURL: baseURL))

        var attempt = 0
        while true {
            attempt += 1

            // Checked before every attempt, not just the first: the UI cancels
            // in-flight searches on each keystroke, and a request that is
            // already sleeping between retries would otherwise burn its whole
            // backoff before noticing nobody wants the answer any more.
            // `APIError.cancelled` rather than `CancellationError` keeps the
            // promise that this method throws only `APIError`.
            if Task.isCancelled { throw APIError.cancelled }

            do {
                return try await perform(request, as: R.self)
            } catch let error as APIError {
                guard retryPolicy.shouldRetry(error, attempt: attempt) else { throw error }
                try await wait(after: error, attempt: attempt)
            }
        }
    }

    // MARK: - Request preparation

    /// Attaches the bearer token, if there is one.
    ///
    /// The token is fetched per request and never stored on the client. That is
    /// what makes rotation and sign-out work without any invalidation step: the
    /// next request simply asks again and gets the new value, or `nil`. A
    /// client that cached the token would keep sending a revoked credential
    /// until something remembered to tell it.
    ///
    /// An `Authorization` header set explicitly on the endpoint is left alone,
    /// so an endpoint needing its own scheme (Basic, or a different token) can
    /// opt out.
    private func authorized(_ request: URLRequest) async -> URLRequest {
        var request = request

        for (field, value) in Self.defaultHeaders where request.value(forHTTPHeaderField: field) == nil {
            request.setValue(value, forHTTPHeaderField: field)
        }

        guard request.value(forHTTPHeaderField: "Authorization") == nil,
              let tokenProvider else {
            return request
        }

        // An empty string is treated as "no token": sending `Bearer ` is a
        // guaranteed 401 and hides the real problem.
        guard let token = await tokenProvider(), !token.isEmpty else {
            return request
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - One attempt

    /// Performs a single attempt: send, record the rate limit, map the status,
    /// decode.
    private func perform<R: Decodable & Sendable>(_ request: URLRequest, as type: R.Type) async throws -> R {
        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw APIError.from(error)
        }

        // Before the status check, so a 4xx still refreshes the budget.
        if let rateLimit = RateLimit(headers: response.allHeaderFields) {
            lastRateLimit = rateLimit
        }

        // The range test comes first so a successful response never pays for
        // parsing an error message it does not have.
        if !(200...299).contains(response.statusCode),
           let error = APIError.from(
               statusCode: response.statusCode,
               message: Self.message(from: data),
               retryAfter: Self.retryAfter(from: response)
           ) {
            throw error
        }

        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIError.from(error)
        }
    }

    // MARK: - Waiting

    /// Sleeps between attempts, preferring the server's `Retry-After`.
    private func wait(after error: APIError, attempt: Int) async throws {
        let seconds: TimeInterval
        // `.some` matches only a 429 that actually carried a usable
        // `Retry-After`; a 429 without one falls through to the backoff.
        if case .rateLimited(.some(let serverDelay)) = error,
           serverDelay.isFinite, serverDelay > 0 {
            // The server told us when the window reopens; guessing shorter just
            // spends an attempt on a guaranteed second 429.
            seconds = serverDelay
        } else {
            seconds = retryPolicy.delay(forAttempt: attempt)
        }

        do {
            try await Task.sleep(nanoseconds: Self.nanoseconds(from: seconds))
        } catch {
            // `Task.sleep` throws only on cancellation.
            throw APIError.cancelled
        }
    }

    /// Converts seconds to nanoseconds without trapping on a hostile or absurd
    /// `Retry-After` (negative, NaN, or past `UInt64.max`).
    private static func nanoseconds(from seconds: TimeInterval) -> UInt64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let nanoseconds = seconds * 1_000_000_000
        guard nanoseconds < Double(UInt64.max) else { return .max }
        return UInt64(nanoseconds)
    }

    // MARK: - Response parsing

    /// Pulls the conventional top-level `message` string out of an error body.
    ///
    /// Best effort by design: a proxy or a gateway can return HTML where the
    /// API would return JSON, and that is not itself worth failing over — the
    /// status code still describes what happened.
    private static func message(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String,
              !message.isEmpty else {
            return nil
        }
        return message
    }

    /// Reads `Retry-After`, which RFC 9110 allows to be either a delay in
    /// seconds or an absolute HTTP date. Both forms are handled; anything else
    /// yields `nil` and the computed backoff is used instead.
    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(raw) {
            return max(0, seconds)
        }

        // Built per call rather than cached in a static: this branch is only
        // reached on a throttled or failing response that chose the date form,
        // and a shared `DateFormatter` would be mutable state visible from
        // every task for no measurable gain.
        //
        // RFC 9110 `IMF-fixdate`. The locale and time zone are pinned because a
        // device set to a non-Gregorian calendar or a 12-hour locale would
        // otherwise fail to parse a perfectly valid header.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"

        guard let date = formatter.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}

// MARK: - Decoding defaults

extension JSONDecoder {

    /// The decoder configured for this API: snake_case keys mapped to Swift
    /// camelCase, and ISO 8601 timestamps.
    ///
    /// A computed property, not a shared instance: `JSONDecoder` is a mutable
    /// class, and one shared across actors would be both a data race and a
    /// place for one caller's configuration change to silently alter another's
    /// decoding.
    static var apiDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
