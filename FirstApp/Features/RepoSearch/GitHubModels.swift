import Foundation

/// A repository as returned by GitHub's search endpoint. Only the fields this
/// feature actually shows are modelled; the rest of the payload is ignored.
struct Repository: Identifiable, Decodable, Sendable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let stargazersCount: Int
    let forksCount: Int
    let language: String?
    let htmlURL: String
    let owner: Owner

    // The decoder uses `.convertFromSnakeCase`, which rewrites the JSON keys
    // *before* matching them against these cases. It lowercases each segment
    // after the first, so `html_url` arrives as `htmlUrl` — not `htmlURL`, and
    // not the original `html_url`. The raw value below is therefore the already
    // converted key. Every other property here round-trips automatically.
    private enum CodingKeys: String, CodingKey {
        case id, name, fullName, description, stargazersCount, forksCount, language, owner
        case htmlURL = "htmlUrl"
    }

    struct Owner: Decodable, Sendable, Hashable {
        let login: String
        let avatarURL: String

        // Same conversion trap as `htmlURL`: `avatar_url` becomes `avatarUrl`.
        private enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatarUrl"
        }
    }
}

struct RepositorySearchResponse: Decodable, Sendable {
    let totalCount: Int
    let items: [Repository]
}

// MARK: - Preview fixtures

extension Repository {
    /// Sample data for SwiftUI previews, so they render without a network call.
    static let previewSwift = Repository(
        id: 44_838_949,
        name: "swift",
        fullName: "swiftlang/swift",
        description: "The Swift Programming Language",
        stargazersCount: 68_214,
        forksCount: 10_412,
        language: "C++",
        htmlURL: "https://github.com/swiftlang/swift",
        owner: Owner(login: "swiftlang", avatarURL: "https://avatars.githubusercontent.com/u/152122611")
    )

    static let previewList: [Repository] = [
        previewSwift,
        Repository(
            id: 4_991_637,
            name: "alamofire",
            fullName: "Alamofire/Alamofire",
            description: "Elegant HTTP Networking in Swift",
            stargazersCount: 41_680,
            forksCount: 7_580,
            language: "Swift",
            htmlURL: "https://github.com/Alamofire/Alamofire",
            owner: Owner(login: "Alamofire", avatarURL: "https://avatars.githubusercontent.com/u/7774181")
        ),
        Repository(
            id: 61_102_336,
            name: "swift-format",
            fullName: "swiftlang/swift-format",
            description: nil,
            stargazersCount: 2_104,
            forksCount: 241,
            language: "Swift",
            htmlURL: "https://github.com/swiftlang/swift-format",
            owner: Owner(login: "swiftlang", avatarURL: "https://avatars.githubusercontent.com/u/152122611")
        )
    ]
}
