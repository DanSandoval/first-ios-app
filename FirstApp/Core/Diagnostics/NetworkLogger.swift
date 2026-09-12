import Foundation
import os

/// Logs HTTP traffic in a form that is safe to ship.
///
/// Everything this type emits has been through ``Redact`` first: URLs lose their
/// query values, headers lose their credentials. Nothing reaches a `Logger`
/// unfiltered.
///
/// ## Bodies are never logged
///
/// Not the request body, not the response body, not a prefix of either, not
/// "just the first 256 bytes for debugging". A request body carries a token on
/// any token-exchange or login call; a response body carries one back on every
/// endpoint that issues credentials, and carries the user's personal data on
/// most of the rest. ``logResponse(_:data:duration:)`` takes the whole `Data`
/// and reads exactly one thing from it — `count` — which is the number you
/// actually want when diagnosing a truncated or empty response.
///
/// If you are chasing a payload-shaped bug, use a proxy against a throwaway
/// account, or a breakpoint. Do not route it through here.
///
/// ## Usage
///
/// ```swift
/// let networkLogger = NetworkLogger()
///
/// networkLogger.logRequest(request, attempt: 1)
/// let start = Date()
/// do {
///     let (data, response) = try await transport.send(request)
///     networkLogger.logResponse(
///         response,
///         data: data,
///         duration: Date().timeIntervalSince(start)
///     )
/// } catch {
///     networkLogger.logFailure(error, request: request, attempt: 1)
///     throw error
/// }
/// ```
///
/// The type is a `Sendable` value holding a `Logger` and a `Bool`, so a single
/// instance can be shared across tasks and actors.
struct NetworkLogger: Sendable {

    /// Where the lines go. Defaults to ``AppLog/networking``.
    private let logger: Logger

    /// When `false`, every method returns immediately.
    ///
    /// This is the coarse switch — a test that does not want log noise, or a
    /// build configuration that turns network logging off wholesale. It is
    /// separate from the system's own per-level filtering, which happens
    /// downstream inside `Logger`.
    ///
    /// Note that redaction runs eagerly when this is `true`, even for a level
    /// the system will go on to discard: parsing one URL and mapping a handful
    /// of header names is not a cost worth measuring next to the HTTP request
    /// it describes.
    private let isEnabled: Bool

    /// Creates a logger.
    ///
    /// - Parameters:
    ///   - logger: The destination. Pass a different `Logger` to route a
    ///     subsystem's traffic into its own category.
    ///   - isEnabled: `false` silences this instance entirely.
    init(logger: Logger = AppLog.networking, isEnabled: Bool = true) {
        self.logger = logger
        self.isEnabled = isEnabled
    }

    // MARK: - Requests

    /// Logs an outgoing request at `.debug`.
    ///
    /// Emits the method, the redacted URL, the redacted header set and the
    /// attempt number. The body is not read.
    ///
    /// - Parameters:
    ///   - request: The request about to be sent.
    ///   - attempt: 1-based attempt counter. A value above 1 is what makes a
    ///     retry storm visible in a log rather than looking like a server that
    ///     was merely called several times.
    func logRequest(_ request: URLRequest, attempt: Int) {
        guard isEnabled else { return }

        let method = request.httpMethod ?? "GET"
        let url = Redact.url(request.url)
        let headers = redactedHeaderSummary(request.allHTTPHeaderFields)

        // `method`, `url` and `attempt` are marked `.public` deliberately: a verb
        // is a fixed token, the URL has already been stripped of query values,
        // and a counter carries no user data. `headers` keeps the default
        // `.private` — the credential-bearing values are gone, but what remains
        // still includes things like a `User-Agent` or a vendor header carrying
        // an account identifier, and "not obviously sensitive" is not the bar.
        logger.debug("→ \(method, privacy: .public) \(url, privacy: .public) attempt=\(attempt, privacy: .public) headers=\(headers)")
    }

    // MARK: - Responses

    /// Logs a completed response, at a level chosen by its status code.
    ///
    /// - 1xx–3xx → `.debug`, the uninteresting case that should not clutter a
    ///   release log.
    /// - 4xx → `.notice`, persisted to the log store. A client-side mistake is
    ///   worth finding later in a sysdiagnose.
    /// - 5xx → `.error`, likewise persisted, and the thing you grep for first.
    ///
    /// - Parameters:
    ///   - response: The HTTP response metadata.
    ///   - data: The body — **used only for `count`**, never logged.
    ///   - duration: Wall-clock time for the request, in seconds. Rendered as
    ///     milliseconds, which is the unit anyone reading a network log is
    ///     thinking in.
    func logResponse(_ response: HTTPURLResponse, data: Data, duration: TimeInterval) {
        guard isEnabled else { return }

        let status = response.statusCode
        let level = Self.level(forStatus: status)
        let url = Redact.url(response.url)
        let milliseconds = Self.milliseconds(duration)

        // `logger.log(level:_:)` rather than three near-identical calls to
        // `.debug`/`.notice`/`.error`. Note that `.notice` is spelled
        // `OSLogType.default` in the type-based API — the same level, two names.
        //
        // `data` appears here once, as `data.count`. That is the only thing this
        // type is ever allowed to read from a body.
        logger.log(level: level, "← \(status, privacy: .public) \(url, privacy: .public) \(data.count, privacy: .public) bytes in \(milliseconds, privacy: .public) ms")
    }

    // MARK: - Failures

    /// Logs a transport-level failure at `.error`.
    ///
    /// The error's domain and code are public: they are fixed constants
    /// (`NSURLErrorDomain`, `-1009`) that say what went wrong without saying
    /// what it went wrong *on*. The description stays private, because framework
    /// errors routinely embed the failing URL — query string included — in their
    /// message and user info.
    ///
    /// - Parameters:
    ///   - error: The thrown error.
    ///   - request: The request that failed, if one was built. `nil` covers
    ///     failures that happen before there is a request to fail.
    ///   - attempt: 1-based attempt counter.
    func logFailure(_ error: Error, request: URLRequest?, attempt: Int) {
        guard isEnabled else { return }

        let method = request?.httpMethod ?? "-"
        let url = Redact.url(request?.url)

        // Every Swift `Error` bridges to `NSError`, so this cast is total and
        // needs no fallback.
        let nsError = error as NSError
        let description = error.localizedDescription

        logger.error("✗ \(method, privacy: .public) \(url, privacy: .public) attempt=\(attempt, privacy: .public) failed: \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public) \(description)")
    }

    // MARK: - Private

    /// Flattens headers into a sorted, redacted `"name: value"` list.
    ///
    /// Sorted so that two log lines for the same request compare cleanly by eye;
    /// `Dictionary` ordering is otherwise arbitrary and varies between runs.
    private func redactedHeaderSummary(_ headers: [String: String]?) -> String {
        guard let headers, !headers.isEmpty else { return "none" }

        return Redact.headers(headers)
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: ", ")
    }

    /// Maps an HTTP status code onto the level its line should be logged at.
    private static func level(forStatus status: Int) -> OSLogType {
        switch status {
        case ..<400:
            // 1xx–3xx grouped with success: a redirect is not a problem, and a
            // release log is more useful for what it leaves out.
            return .debug
        case 400..<500:
            // `.notice` in the message-level vocabulary, `.default` in the
            // `OSLogType` one. Persisted to the log store, unlike `.debug`.
            return .default
        default:
            return .error
        }
    }

    /// Renders a duration in seconds as fixed-point milliseconds.
    ///
    /// Formatted ahead of the interpolation rather than with `Logger`'s own
    /// float formatting so the output is locale-independent — `String(format:)`
    /// with no locale argument always produces a `.` decimal separator, which
    /// keeps logs from a device set to a comma-decimal locale comparable with
    /// everyone else's.
    private static func milliseconds(_ duration: TimeInterval) -> String {
        String(format: "%.1f", duration * 1000)
    }
}
