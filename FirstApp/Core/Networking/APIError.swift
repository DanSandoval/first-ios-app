import Foundation

/// Every way a request can fail, flattened into one comparable value.
///
/// `Equatable` is deliberate: it lets a test write
/// `XCTAssertEqual(error, .rateLimited(retryAfter: 30))` instead of pattern
/// matching its way through an opaque `Error`. That is also why the cases carry
/// *description strings* rather than wrapping the underlying `Error` — `Error`
/// is not `Equatable`, so boxing one would poison the conformance. The cost is
/// that the original error object is not recoverable from an `APIError`; the
/// human-readable summary is preserved instead.
enum APIError: Error, Equatable, Sendable {

    /// The base URL and endpoint path could not be composed into a valid URL.
    case invalidURL

    /// The request never produced an HTTP response: offline, DNS failure, TLS
    /// failure, timeout. `code` is the underlying `URLError.Code`.
    case transport(code: URLError.Code, description: String)

    /// A non-2xx response that is not covered by a more specific case.
    /// `message` is the server's own explanation when the body carried one.
    case http(status: Int, message: String?)

    /// 401. The credential is missing, expired, or rejected.
    case unauthorized

    /// 429. `retryAfter` is the server's `Retry-After` value in seconds, when
    /// it sent one.
    case rateLimited(retryAfter: TimeInterval?)

    /// The response was 2xx but its body did not match the expected shape.
    case decoding(description: String)

    /// The task was cancelled — by an explicit `cancel()`, or by the enclosing
    /// task being torn down. Never surface this to the user as a failure.
    case cancelled
}

// MARK: - User-facing text

extension APIError: LocalizedError {

    /// A sentence written **for the person using the app**, not for the
    /// engineer reading the logs. Nothing here names a type, a status code
    /// alone, or a coding path; the developer detail stays in the associated
    /// values for logging.
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That address could not be opened."

        case .transport:
            return "Couldn't reach the server. Check your connection and try again."

        case .http(let status, let message):
            // The server's own message is usually the most useful thing a user
            // can be told ("Repository not found"), so prefer it when present.
            if let message, !message.isEmpty {
                return message
            }
            return "The server had a problem completing that request (\(status))."

        case .unauthorized:
            return "You're signed out, or your access has expired. Sign in and try again."

        case .rateLimited(let retryAfter):
            guard let retryAfter, retryAfter.isFinite, retryAfter > 0 else {
                return "Too many requests. Try again in a moment."
            }
            let seconds = Int(retryAfter.rounded(.up))
            let unit = seconds == 1 ? "second" : "seconds"
            return "Too many requests. Try again in \(seconds) \(unit)."

        case .decoding:
            // Deliberately vague: a coding path means nothing to a user, and
            // there is nothing they can do about it.
            return "The server sent something the app couldn't read."

        case .cancelled:
            return "That request was cancelled."
        }
    }
}

// MARK: - Retry classification

extension APIError {

    /// Whether retrying the *same* request could plausibly succeed.
    ///
    /// This is the single source of truth for retryability;
    /// ``RetryPolicy/shouldRetry(_:attempt:)`` layers the attempt budget on top
    /// of it rather than repeating the classification.
    ///
    /// Retryable: transport failures, rate limiting, and 5xx — all transient.
    /// Not retryable: cancellation (intended), 401 (the credential will not fix
    /// itself), decoding and invalid URL (deterministic client bugs), and 4xx
    /// other than 429 (the request itself is wrong).
    var isRetryable: Bool {
        switch self {
        case .transport, .rateLimited:
            return true
        case .http(let status, _):
            return status >= 500
        case .invalidURL, .unauthorized, .decoding, .cancelled:
            return false
        }
    }
}

// MARK: - Mapping raw failures

extension APIError {

    /// Normalises anything thrown by the transport or the decoder into an
    /// `APIError`.
    ///
    /// - `URLError` becomes ``transport(code:description:)``, except
    ///   `URLError.cancelled`, which becomes ``cancelled`` so that a torn-down
    ///   request is never mistaken for a network fault.
    /// - `DecodingError` becomes ``decoding(description:)`` with the coding
    ///   path baked into the description.
    /// - An `APIError` passes through untouched.
    /// - Anything else becomes a transport failure with `URLError.Code.unknown`.
    static func from(_ error: Error) -> APIError {
        switch error {
        case let apiError as APIError:
            return apiError

        case is CancellationError:
            return .cancelled

        case let urlError as URLError:
            if urlError.code == .cancelled {
                return .cancelled
            }
            return .transport(code: urlError.code, description: urlError.localizedDescription)

        case let decodingError as DecodingError:
            return .decoding(description: describe(decodingError))

        default:
            return .transport(code: .unknown, description: error.localizedDescription)
        }
    }

    /// Maps an HTTP status onto the matching case, or `nil` when the status is
    /// a success and there is nothing to report.
    ///
    /// - Parameters:
    ///   - statusCode: The response's status code.
    ///   - message: A human-readable explanation pulled from the response body,
    ///     when the body carried one.
    ///   - retryAfter: The parsed `Retry-After` value in seconds, used only for
    ///     429.
    static func from(statusCode: Int, message: String?, retryAfter: TimeInterval? = nil) -> APIError? {
        switch statusCode {
        case 200...299:
            return nil
        case 401:
            return .unauthorized
        case 429:
            return .rateLimited(retryAfter: retryAfter)
        default:
            return .http(status: statusCode, message: message)
        }
    }

    /// Renders a `DecodingError` as a one-line summary that names the field
    /// that went wrong. Without the coding path these errors are nearly
    /// impossible to act on, since "expected String" says nothing about *where*.
    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing field '\(key.stringValue)' at \(path(context))."
        case .typeMismatch(let type, let context):
            return "Expected \(type) at \(path(context))."
        case .valueNotFound(let type, let context):
            return "Expected \(type) at \(path(context)) but the value was null."
        case .dataCorrupted(let context):
            return "Malformed data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return "The response did not match the expected format."
        }
    }

    /// Formats a coding path as a dotted trail, e.g. `items.3.created_at`.
    private static func path(_ context: DecodingError.Context) -> String {
        let components = context.codingPath.map { key -> String in
            // Array indices carry an `intValue`; object keys carry a name.
            if let index = key.intValue {
                return String(index)
            }
            return key.stringValue
        }
        return components.isEmpty ? "the top level" : components.joined(separator: ".")
    }
}
