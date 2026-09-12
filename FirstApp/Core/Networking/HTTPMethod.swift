import Foundation

/// The HTTP verb an ``Endpoint`` is sent with.
///
/// The raw value is the exact token written onto the wire, so it can be handed
/// to `URLRequest.httpMethod` without any further translation.
enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}
