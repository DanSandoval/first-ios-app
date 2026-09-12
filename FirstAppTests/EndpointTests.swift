import Foundation
import XCTest
@testable import FirstApp

/// URL composition only -- nothing here touches a transport.
final class EndpointTests: XCTestCase {

    private let base = URL(string: "https://api.example.com")!

    /// `Endpoint` is generic over its response type, but none of these tests
    /// decode anything, so the cheapest possible stand-in will do.
    private struct Ignored: Decodable, Sendable {}

    // MARK: - Path

    func testLeadingSlashAndBarePathResolveIdentically() throws {
        let withSlash = try Endpoint<Ignored>(path: "/users").urlRequest(baseURL: base)
        let without = try Endpoint<Ignored>(path: "users").urlRequest(baseURL: base)

        // The trap here is `URL.appendingPathComponent`, which does not strip a
        // leading slash and happily produces "https://api.example.com//users".
        XCTAssertEqual(withSlash.url?.absoluteString, "https://api.example.com/users")
        XCTAssertEqual(without.url?.absoluteString, "https://api.example.com/users")
    }

    func testPathIsAppendedToABaseURLThatAlreadyHasOne() throws {
        let versioned = URL(string: "https://api.example.com/v1")!

        let request = try Endpoint<Ignored>(path: "/users").urlRequest(baseURL: versioned)

        // Appended, not replaced. `URL(string:relativeTo:)` would drop "/v1".
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/users")
    }

    func testNestedPathSurvivesIntact() throws {
        let request = try Endpoint<Ignored>(path: "/users/dan/repos").urlRequest(baseURL: base)

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/users/dan/repos")
    }

    // MARK: - Query

    func testQueryValuesArePercentEncoded() throws {
        let endpoint = Endpoint<Ignored>(
            path: "/search",
            query: [
                URLQueryItem(name: "q", value: "hello world"),
                URLQueryItem(name: "tag", value: "a+b")
            ]
        )

        let url = try XCTUnwrap(endpoint.urlRequest(baseURL: base).url)
        let string = url.absoluteString

        XCTAssertTrue(
            string.contains("q=hello%20world"),
            "A space must be percent-encoded. Got: \(string)"
        )
        // `+` is a legal sub-delim in a query, so URLComponents passes it
        // through verbatim -- and any server that form-decodes the query then
        // reads it back as a space. `%2B` is a literal plus under both
        // readings, so it is the only unambiguous spelling.
        XCTAssertTrue(
            string.contains("tag=a%2Bb"),
            "A literal '+' must be encoded as %2B or it decodes to a space server-side. Got: \(string)"
        )

        // Exact, not just `contains`: this also pins the item order and proves
        // nothing else in the query was rewritten along the way.
        XCTAssertEqual(url.query, "q=hello%20world&tag=a%2Bb")
    }

    func testQueryItemNamesArePercentEncodedToo() throws {
        let endpoint = Endpoint<Ignored>(
            path: "/search",
            query: [URLQueryItem(name: "a+b", value: "c")]
        )

        let url = try XCTUnwrap(endpoint.urlRequest(baseURL: base).url)

        // A name is form-decoded by the server exactly like a value is.
        XCTAssertEqual(url.query, "a%2Bb=c")
    }

    func testLiteralPlusInThePathSurvivesAlongsideAnEncodedQuery() throws {
        let endpoint = Endpoint<Ignored>(
            path: "/tags/a+b",
            query: [URLQueryItem(name: "tag", value: "c+d")]
        )

        let url = try XCTUnwrap(endpoint.urlRequest(baseURL: base).url)

        // The `+` correction is deliberately scoped to the query component. A
        // `+` in a path is not form-decoded in practice, so encoding it would
        // change a URL that was already right. This is the test that fails if
        // anyone later "simplifies" that fix into a replacement over the whole
        // URL string.
        XCTAssertEqual(url.absoluteString, "https://api.example.com/tags/a+b?tag=c%2Bd")
    }

    func testEmptyQueryProducesNoTrailingQuestionMark() throws {
        let url = try XCTUnwrap(Endpoint<Ignored>(path: "/users").urlRequest(baseURL: base).url)

        // A bare "?" is legal but ugly, and it breaks naive URL equality checks
        // and response caches that key on the full string.
        XCTAssertEqual(url.absoluteString, "https://api.example.com/users")
        XCTAssertFalse(url.absoluteString.contains("?"), "Empty query left a dangling '?'")
    }

    func testMultipleQueryItemsAreJoinedWithAmpersands() throws {
        let endpoint = Endpoint<Ignored>(
            path: "/search",
            query: [
                URLQueryItem(name: "page", value: "2"),
                URLQueryItem(name: "per_page", value: "50")
            ]
        )

        let url = try XCTUnwrap(endpoint.urlRequest(baseURL: base).url)

        XCTAssertEqual(url.query, "page=2&per_page=50")
    }

    // MARK: - Method, headers, body

    func testDefaultMethodIsGET() throws {
        let request = try Endpoint<Ignored>(path: "/users").urlRequest(baseURL: base)

        XCTAssertEqual(request.httpMethod, HTTPMethod.get.rawValue)
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testMethodHeadersAndBodyLandOnTheRequest() throws {
        let body = Data(#"{"name":"dan"}"#.utf8)
        let endpoint = Endpoint<Ignored>(
            path: "/users",
            method: .post,
            headers: ["X-Test": "yes", "Content-Type": "application/json"],
            body: body
        )

        let request = try endpoint.urlRequest(baseURL: base)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "yes")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, body)
    }

    func testNoBodyMeansNoBody() throws {
        let request = try Endpoint<Ignored>(path: "/users").urlRequest(baseURL: base)

        XCTAssertNil(request.httpBody)
    }
}
