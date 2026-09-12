import Foundation
@testable import FirstApp

/// A scripted `HTTPTransport` that records every request it was handed.
///
/// Why a `final class` + `NSLock` rather than an `actor`: `APIClient` is an
/// actor, so it calls `send` from its own executor while the test body
/// inspects the recorded requests from the test's executor -- the mock has to
/// be safe under that. An actor would be safe too, but it would force every
/// assertion (`transport.requestCount`, `transport.lastRequest`) to be
/// `await`ed and would make the scripting helpers async for no benefit. One
/// lock guarding all mutable state keeps the assertions synchronous. The
/// `@unchecked` is honest about the trade: the compiler cannot see the lock,
/// but neither stored property below is ever touched outside it.
final class MockTransport: HTTPTransport, @unchecked Sendable {

    /// One scripted outcome. `send` consumes these front to back, one per
    /// call, so a retry test just queues two of them.
    enum Outcome {
        /// Turned into an `HTTPURLResponse` at send time, against the
        /// request's own URL -- which is what a real transport returns.
        case response(status: Int, body: Data, headers: [String: String])
        case failure(Error)
    }

    enum Failure: Error, Equatable {
        /// `send` was called more often than the test queued outcomes for.
        /// Almost always means a retry happened that was not expected.
        case queueExhausted(afterCalls: Int)
        case unbuildableResponse(url: URL?)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var recorded: [URLRequest] = []

    init(_ outcomes: [Outcome] = []) {
        self.outcomes = outcomes
    }

    // MARK: - Scripting

    func enqueue(_ outcome: Outcome) {
        lock.lock()
        defer { lock.unlock() }
        outcomes.append(outcome)
    }

    // MARK: - Recorded traffic

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var requestCount: Int { requests.count }

    var lastRequest: URLRequest? { requests.last }

    // MARK: - HTTPTransport

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        recorded.append(request)
        let calls = recorded.count
        let next = outcomes.isEmpty ? nil : outcomes.removeFirst()
        lock.unlock()

        guard let next else { throw Failure.queueExhausted(afterCalls: calls) }

        switch next {
        case .failure(let error):
            throw error

        case .response(let status, let body, let headers):
            guard
                let url = request.url,
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                )
            else {
                throw Failure.unbuildableResponse(url: request.url)
            }
            return (body, response)
        }
    }
}

extension MockTransport.Outcome {

    /// A JSON body written as a Swift string literal, so the fixtures in the
    /// tests read as the JSON the server would actually send.
    static func json(
        _ body: String,
        status: Int = 200,
        headers: [String: String] = [:]
    ) -> Self {
        var headers = headers
        headers["Content-Type"] = headers["Content-Type"] ?? "application/json"
        return .response(status: status, body: Data(body.utf8), headers: headers)
    }

    /// A bodiless status code, for the cases where only the status matters.
    static func status(_ status: Int, headers: [String: String] = [:]) -> Self {
        .response(status: status, body: Data(), headers: headers)
    }
}
