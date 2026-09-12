//
//  Redaction.swift
//
//  THE RULE FOR THIS FILE, AND FOR EVERY CALLER OF IT:
//
//      NEVER LOG A CREDENTIAL, AND NEVER LOG A REQUEST OR RESPONSE BODY.
//
//  Not at `.debug`, not behind `#if DEBUG`, not "temporarily". A log line
//  written on a developer's machine is a log line that ships, and once it ships
//  the value it prints lands in the device's log store, in every sysdiagnose the
//  user is ever asked to send to AppleCare, and in bug reports forwarded through
//  channels nobody audited. `Logger`'s `.private` default helps, but it is the
//  second line of defence; this file is the first.
//
//  Credentials in this app: the GitHub token in the Keychain, the `Authorization`
//  header built from it, and anything a server chooses to echo back in a body.
//  Bodies are called out separately because they are the easiest place to get
//  this wrong — a token appears in a request body on a token-exchange call and
//  in a response body on any endpoint that hands one back.
//

import Foundation

/// Turns values that may contain secrets into strings that are safe to log.
///
/// Everything here is deliberately lossy and one-way. The goal is a log line
/// that is still *useful in a bug report* — you can tell two tokens apart, see
/// which endpoint was hit, see which headers were present — while being useless
/// to anyone who obtains the log.
///
/// The bias throughout is toward over-redaction. A denylist cannot anticipate
/// every header name or query parameter a future API will invent, so where there
/// is a choice, these helpers redact more than strictly necessary. A log that
/// omits something you wanted costs you one build; a log that prints a token
/// costs the user their account.
///
/// ## Expected behaviour
///
/// ``token(_:)``
/// ```
/// nil                                          → "<none>"
/// ""                                           → "<redacted>"
/// "abc123"                                     → "<redacted>"           (too short)
/// "ghp_0123456789abcdef0123456789abcdefab12"   → "<token 4 chars …ab12, len 40>"
/// ```
///
/// ``url(_:)``
/// ```
/// nil                                          → "<no url>"
/// https://api.github.com/user                  → "https://api.github.com/user"
/// https://api.github.com/u?access_token=ghp_x  → "https://api.github.com/u?access_token=<redacted>"
/// https://api.github.com/s?q=swift&page=2      → "https://api.github.com/s?q=<redacted>&page=<redacted>"
/// https://user:pw@example.com/x                → "https://example.com/x"  (userinfo dropped)
/// https://example.com/cb#access_token=ghp_x    → "https://example.com/cb#<redacted>"
/// https://example.com:8443/health              → "https://example.com:8443/health"
/// ```
///
/// ``headers(_:)``
/// ```
/// ["Authorization": "Bearer ghp_x"]            → ["Authorization": "<redacted>"]
/// ["authorization": "Bearer ghp_x"]            → ["authorization": "<redacted>"]   (case-insensitive)
/// ["X-Api-Key": "k"]                           → ["X-Api-Key": "<redacted>"]
/// ["X-Refresh-Token": "t"]                     → ["X-Refresh-Token": "<redacted>"] (substring)
/// ["Accept": "application/json"]               → ["Accept": "application/json"]    (kept)
/// ```
///
/// ``email(_:)``
/// ```
/// nil                                          → "<none>"
/// "dan@example.com"                            → "d***@example.com"
/// "d@example.com"                              → "***@example.com"      (1-char local part)
/// "not-an-email"                               → "<redacted>"
/// ```
enum Redact {

    /// The stand-in written wherever a value was removed.
    ///
    /// A fixed marker rather than an empty string, so a reader can tell
    /// "redacted" apart from "absent" — the difference matters when you are
    /// working out whether a header was ever set.
    static let marker = "<redacted>"

    /// Number of trailing characters of a token kept as a fingerprint.
    private static let tokenFingerprintLength = 4

    /// Tokens at or below this length are redacted whole.
    ///
    /// Four characters out of a 40-character token is a tenth of it and not
    /// brute-forceable on its own; four characters out of an 8-character secret
    /// is half the secret. Rather than pick a clever ratio, anything short is
    /// treated as "all of it is sensitive".
    private static let minimumFingerprintableLength = 12

    // MARK: - Credentials

    /// Reduces a token to a fingerprint that identifies it without exposing it.
    ///
    /// The point is triage. Given two bug reports you need to know whether the
    /// same credential was in play, and given one report you need to know
    /// whether the token was truncated in transit — a length plus four
    /// characters answers both, and answers nothing else.
    ///
    /// The *trailing* characters are kept, not the leading ones, because issued
    /// credentials tend to start with a fixed, publicly known prefix (`ghp_`,
    /// `github_pat_`, `sk_live_`). Leading characters would carry almost no
    /// entropy and so would distinguish almost nothing.
    ///
    /// - Parameter value: The token, or `nil` if there is none.
    /// - Returns: `"<none>"` for `nil`, ``marker`` for anything short enough
    ///   that a fingerprint would give away a meaningful fraction of it, and
    ///   otherwise a string of the form `"<token 4 chars …ab12, len 40>"`.
    static func token(_ value: String?) -> String {
        guard let value else { return "<none>" }

        let length = value.count
        guard length > minimumFingerprintableLength else { return marker }

        let fingerprint = String(value.suffix(tokenFingerprintLength))
        return "<token \(tokenFingerprintLength) chars …\(fingerprint), len \(length)>"
    }

    // MARK: - URLs

    /// Rebuilds a URL as scheme, host, port and path, with every query value
    /// replaced by ``marker``.
    ///
    /// Query *keys* are kept, because `?access_token=<redacted>` tells you far
    /// more during debugging than `?<redacted>` does, and a key is a name the
    /// API vendor already documents publicly.
    ///
    /// Every value goes, including ones that look harmless. Credentials reach
    /// query strings constantly — legacy `?access_token=`, `?api_key=`,
    /// pre-signed download URLs whose entire signature is a query parameter —
    /// and a per-key denylist would have to be updated every time an API adds a
    /// parameter. Losing `?page=2` from a log costs nothing by comparison.
    ///
    /// Two parts of the URL are dropped rather than redacted in place:
    ///
    /// - **Userinfo** (`https://user:password@host/…`) is omitted entirely. It
    ///   is a credential with no diagnostic value.
    /// - **The fragment** is replaced wholesale, not parsed. OAuth implicit-flow
    ///   redirects deliver `#access_token=…` in the fragment, so it is treated
    ///   as opaque and sensitive.
    ///
    /// - Parameter url: The URL, or `nil`.
    /// - Returns: A loggable string; `"<no url>"` for `nil` and
    ///   `"<unparsable url>"` if the URL cannot be decomposed.
    static func url(_ url: URL?) -> String {
        guard let url else { return "<no url>" }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return "<unparsable url>"
        }

        var result = ""

        if let scheme = components.scheme {
            result += "\(scheme)://"
        }

        // `components.user` and `.password` are intentionally never read.
        if let host = components.host {
            result += host
            if let port = components.port {
                result += ":\(port)"
            }
        }

        result += components.path

        if let items = components.queryItems, !items.isEmpty {
            let redacted = items.map { item in
                // A valueless item (`?flag`) has nothing to hide; keeping the
                // bare key avoids inventing a value that was never sent.
                item.value == nil ? item.name : "\(item.name)=\(marker)"
            }
            result += "?" + redacted.joined(separator: "&")
        } else if components.query != nil {
            // A query string that would not decompose into items. Unparsed
            // means unredactable, so none of it survives.
            result += "?" + marker
        }

        if components.fragment != nil {
            result += "#" + marker
        }

        return result.isEmpty ? "<unparsable url>" : result
    }

    // MARK: - Headers

    /// Header names whose values are always secrets, matched in full.
    ///
    /// Stored lowercased; ``isSensitiveHeader(_:)`` lowercases its input before
    /// comparing, because HTTP header names are case-insensitive and the casing
    /// you get back from `URLRequest` is whatever the caller happened to type.
    private static let sensitiveHeaderNames: Set<String> = [
        "authorization",
        "cookie",
        "set-cookie",
        "proxy-authorization",
        "x-api-key"
    ]

    /// Substrings that make a header name suspicious wherever they appear.
    ///
    /// This is the catch-all for the endless supply of vendor headers —
    /// `X-Refresh-Token`, `X-Client-Secret`, `X-Amz-Security-Token`. It
    /// over-matches on purpose: `key` also matches a header like `X-Monkey-Id`,
    /// and redacting that is a trivial cost next to missing a real secret.
    private static let sensitiveHeaderFragments = [
        "token",
        "secret",
        "password",
        "key"
    ]

    /// Reports whether a header's value must be withheld from logs.
    ///
    /// Matching is case-insensitive via `lowercased()`, which applies
    /// locale-independent Unicode case mapping — unlike
    /// `lowercased(with: .current)`, it cannot be thrown off by a device set to
    /// a Turkish locale, where `"I"` lowercases to a dotless `"ı"` and an
    /// `"AUTHORIZATION"` header would otherwise slip past this check.
    ///
    /// - Parameter name: The header field name.
    /// - Returns: `true` if the value should be replaced with ``marker``.
    static func isSensitiveHeader(_ name: String) -> Bool {
        let lowercased = name.lowercased()

        if sensitiveHeaderNames.contains(lowercased) { return true }

        return sensitiveHeaderFragments.contains { lowercased.contains($0) }
    }

    /// Replaces the value of every sensitive header with ``marker``, keeping all
    /// names.
    ///
    /// Names are kept even when redacted: "an `Authorization` header was
    /// present" and "no `Authorization` header was sent" are different bugs, and
    /// dropping the entry would make them look identical.
    ///
    /// - Parameter headers: The header dictionary, e.g.
    ///   `URLRequest.allHTTPHeaderFields`.
    /// - Returns: A dictionary with the same keys and sensitive values removed.
    static func headers(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { result, entry in
            result[entry.key] = isSensitiveHeader(entry.key) ? marker : entry.value
        }
    }

    // MARK: - Personal data

    /// Reduces an email address to its first character and its domain.
    ///
    /// Not a credential, but personal data, and the same reasoning applies: the
    /// domain is what you actually need in support triage ("all the failures are
    /// on one corporate mail host"), while the local part is what identifies the
    /// person.
    ///
    /// The split is on the **last** `@`, since a quoted local part may legally
    /// contain one. A single-character local part is masked entirely — showing
    /// "the first character" of a one-character string shows all of it.
    ///
    /// - Parameter value: The address, or `nil`.
    /// - Returns: `"<none>"` for `nil`, ``marker`` for anything that is not
    ///   shaped like an address, otherwise e.g. `"d***@example.com"`.
    static func email(_ value: String?) -> String {
        guard let value else { return "<none>" }
        guard let atIndex = value.lastIndex(of: "@") else { return marker }

        let local = value[value.startIndex..<atIndex]
        let domain = value[value.index(after: atIndex)...]

        guard !domain.isEmpty else { return marker }
        guard let initial = local.first, local.count > 1 else { return "***@\(domain)" }

        return "\(initial)***@\(domain)"
    }
}
