import Foundation

/// One API call, described independently of the client that sends it.
///
/// The generic parameter is the type the response body decodes into, so the
/// return type of ``APIClient/send(_:)`` follows from the endpoint itself and
/// callers never restate it:
///
/// ```swift
/// let repos = Endpoint<[Repository]>(path: "users/octocat/repos")
/// let result = try await client.send(repos)   // -> [Repository]
/// ```
///
/// `path` is given **unencoded**: percent-encoding is applied by
/// `URLComponents` in ``urlRequest(baseURL:)``. Passing an already-encoded path
/// would double-encode it.
struct Endpoint<Response: Decodable & Sendable>: Sendable {

    /// Path relative to the client's base URL. A leading slash is optional and
    /// makes no difference — `"users"` and `"/users"` compose identically.
    var path: String

    /// The HTTP verb. Defaults to `.get`.
    var method: HTTPMethod = .get

    /// Query items, appended by `URLComponents`. An empty array produces a URL
    /// with no `?` at all.
    ///
    /// Values are given unencoded. A literal `+` is encoded as `%2B` rather
    /// than passed through, so it survives servers that form-decode the query
    /// string; see ``urlRequest(baseURL:)``.
    var query: [URLQueryItem] = []

    /// Per-endpoint headers. These take precedence over any default header the
    /// client would otherwise apply.
    var headers: [String: String] = [:]

    /// Request body, already serialised. Leave `nil` for `GET`.
    var body: Data? = nil

    /// Creates an endpoint.
    ///
    /// - Parameters:
    ///   - path: Unencoded path relative to the base URL, with or without a
    ///     leading slash.
    ///   - method: HTTP verb. Defaults to `.get`.
    ///   - query: Query items. Defaults to none.
    ///   - headers: Headers that override the client's defaults. Defaults to none.
    ///   - body: Serialised request body. Defaults to `nil`.
    init(
        path: String,
        method: HTTPMethod = .get,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// Composes this endpoint against a base URL into a ready-to-send request.
    ///
    /// Path joining is done through `URLComponents` rather than
    /// `URL(string:relativeTo:)`. That initialiser follows RFC 3986 relative
    /// resolution, which **discards the base URL's last path component** — so
    /// `"v3"` resolved against `https://host/api/` gives `https://host/api/v3`,
    /// but against `https://host/api` it gives `https://host/v3`, silently
    /// losing `/api`. Joining the paths explicitly removes that trap and makes
    /// the leading slash on `path` irrelevant.
    ///
    /// Percent-encoding is left to `URLComponents`: assigning to `.path` and
    /// `.queryItems` encodes each piece with the correct character set for its
    /// position, which hand-rolled escaping reliably gets wrong. The single
    /// exception is a literal `+` in the query, which is rewritten to `%2B` —
    /// the reasoning is inline below.
    ///
    /// - Parameter baseURL: The API root, e.g. `https://api.github.com` or
    ///   `https://example.com/api/v3`.
    /// - Returns: A request with method, headers, body, and final URL set.
    /// - Throws: ``APIError/invalidURL`` if the pieces do not form a valid URL.
    func urlRequest(baseURL: URL) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }

        // Join with exactly one separator, whatever the two halves bring.
        let base = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        let suffix = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components.path = suffix.isEmpty ? base : base + "/" + suffix

        // nil, not [], so an endpoint without query items produces no trailing
        // "?" — some servers and most cache keys treat the two URLs as distinct.
        components.queryItems = query.isEmpty ? nil : query

        // One correction on top of what URLComponents produced: a literal "+".
        //
        // RFC 3986 calls "+" a legal sub-delim in a query, so URLComponents
        // passes it through verbatim — spec-correct, and a silent bug. Any
        // server that form-decodes the query string reads that "+" back as a
        // space, so a search for "a+b" arrives as "a b" with nothing anywhere
        // reporting a problem. GitHub's search API decodes exactly that way.
        // "%2B" means a literal plus under both readings, so it is the only
        // unambiguous spelling.
        //
        // A blanket replacement is safe: URLComponents encodes a space as
        // "%20" and never as "+", so every "+" left in the encoded query came
        // from a literal "+" in a name or value. It also cannot produce an
        // invalid string — "%2B" is a well-formed triplet and "+" can never
        // appear inside an existing one — which matters because the
        // `percentEncodedQuery` setter traps on malformed input. Do not feed
        // that setter anything not derived from its own getter.
        if let encodedQuery = components.percentEncodedQuery, encodedQuery.contains("+") {
            components.percentEncodedQuery = encodedQuery.replacingOccurrences(of: "+", with: "%2B")
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body

        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        return request
    }
}
