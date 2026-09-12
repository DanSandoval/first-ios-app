import Foundation

/// The one thing ``APIClient`` needs from the network: hand over a request, get
/// back bytes and an HTTP response.
///
/// This protocol exists purely so tests can inject a stub. `URLSession` is a
/// concrete class with no useful seam for substituting canned responses without
/// resorting to `URLProtocol` subclasses or a live server, so the client depends
/// on this one-method abstraction instead and a test passes in a stub that
/// returns whatever `(Data, HTTPURLResponse)` pair the case under test needs.
protocol HTTPTransport: Sendable {

    /// Performs one request. Implementations do **no** retrying — retry policy
    /// lives in ``APIClient`` so that a stub transport stays trivially simple.
    ///
    /// - Parameter request: The fully formed request, headers included.
    /// - Returns: The response body and its HTTP metadata.
    /// - Throws: Whatever the underlying transport failed with. ``APIClient``
    ///   normalises it through ``APIError/from(_:)``.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {

    /// Bridges `URLSession.data(for:)` onto ``HTTPTransport``.
    ///
    /// `data(for:)` is typed as returning a `URLResponse`; for any request with
    /// an `http`/`https` URL it is always an `HTTPURLResponse`, but the compiler
    /// cannot know that, so the downcast is checked and reported as a transport
    /// failure rather than force-unwrapped.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport(
                code: .badServerResponse,
                description: "The server's reply was not an HTTP response."
            )
        }

        return (data, httpResponse)
    }
}
