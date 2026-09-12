import CryptoKit
import Foundation

/// A file-backed, TTL-aware cache for `Codable` values.
///
/// `DiskCache` is an `actor`, so every read and write is serialised by the
/// runtime and callers need no lock of their own. Each entry is one JSON file
/// on disk holding a small envelope (`storedAt`, `expiresAt`, `payload`), so a
/// single corrupt or half-written entry can never take the rest of the cache
/// with it.
///
/// ### Where the files live
/// The default is `.cachesDirectory`. iOS is free to purge that directory when
/// the device is low on storage, and it is excluded from iCloud/iTunes backups.
/// That is exactly right for data you can re-fetch — a cached API response —
/// and exactly wrong for anything the user would be upset to lose. For user
/// data (drafts, documents, anything not reproducible from the server) pass
/// `.documentDirectory` instead, and accept that those bytes then count against
/// the user's backup and storage.
///
/// ### Usage
/// ```swift
/// let cache = try DiskCache(name: "api-responses", defaultTTL: 600)
/// try await cache.store(profile, for: "profile/\(userID)")
/// let cached = try await cache.load(Profile.self, for: "profile/\(userID)")
/// ```
///
/// ### Failure philosophy
/// A cache must never be able to brick the app. An entry that is missing,
/// unreadable, expired, or undecodable is reported as a miss (`nil`) and
/// evicted — never thrown at the caller. Only genuine programmer errors
/// (an invalid cache name, an unavailable search-path directory) and encoding
/// failures during `store` surface as thrown errors.
actor DiskCache {

    // MARK: - Stored state

    /// The directory this cache owns. Exposed for diagnostics and tests; it is
    /// immutable and `Sendable`, so reading it needs no `await`.
    nonisolated let directoryURL: URL

    /// TTL applied by `store(_:for:ttl:)` when the caller does not pass one.
    private let defaultTTL: TimeInterval

    /// A private `FileManager` instance rather than `.default`, so this actor's
    /// file operations cannot be affected by another subsystem configuring the
    /// shared manager.
    private let fileManager = FileManager()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Extension used for every entry file. Enumeration (`removeAll`,
    /// `removeExpired`, `diskSizeBytes`) filters on it, so a stray file dropped
    /// into the directory by something else is never enumerated or deleted.
    private static let fileExtension = "cache"

    /// Subdirectory namespace under the chosen search-path directory, so this
    /// type only ever enumerates paths it created itself.
    private static let namespace = "DiskCache"

    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    /// `.atomic` writes to a temporary file and renames it into place, so a
    /// crash mid-write leaves either the old entry or the new one — never a
    /// truncated file that fails to decode forever.
    ///
    /// The protection class is stated explicitly rather than inherited: cached
    /// server responses stay unreadable until the device has been unlocked once
    /// after boot, which still permits background refreshes.
    private static let writeOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication
    ]
    #else
    private static let writeOptions: Data.WritingOptions = [.atomic]
    #endif

    // MARK: - Lifecycle

    /// Creates (or adopts) a cache directory.
    ///
    /// - Parameters:
    ///   - name: Directory name for this cache, scoping it away from other
    ///     caches in the same app. Restricted to `A-Z a-z 0-9 - _ .` and at
    ///     most 64 characters; anything else throws
    ///     ``DiskCacheError/invalidCacheName(_:)``. The name is developer
    ///     supplied, so rejecting a bad one loudly at startup beats silently
    ///     rewriting it into something that resolves elsewhere on disk.
    ///   - directory: Search-path directory to create the cache under. Defaults
    ///     to `.cachesDirectory`; see the type documentation for when
    ///     `.documentDirectory` is the right choice instead.
    ///   - defaultTTL: Lifetime applied when `store` is called without an
    ///     explicit `ttl`. Defaults to 300 seconds. A value that is zero,
    ///     negative, or non-finite means entries do not expire on their own.
    /// - Throws: ``DiskCacheError`` if the name is invalid or the directory
    ///   cannot be located, or an underlying `FileManager` error if the
    ///   directory cannot be created.
    init(name: String,
         directory: FileManager.SearchPathDirectory = .cachesDirectory,
         defaultTTL: TimeInterval = 300) throws {
        self.directoryURL = try Self.prepareDirectory(name: name, directory: directory)
        self.defaultTTL = defaultTTL

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        // Seconds-since-1970 keeps full sub-second precision (unlike ISO 8601
        // without fractional seconds) and is stable across OS versions. The two
        // strategies must stay in sync: changing one without the other makes
        // every existing entry undecodable — which degrades to a cache miss
        // rather than a crash, but silently throws away the whole cache.
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - Writing

    /// Stores a value under `key`, replacing any existing entry.
    ///
    /// The write is atomic, so an interrupted store leaves the previous entry
    /// intact rather than a truncated file.
    ///
    /// - Parameters:
    ///   - value: The value to persist. Encoded as JSON.
    ///   - key: Cache key. Any string is safe — see ``fileURL(for:)`` for why.
    ///   - ttl: Lifetime for this entry. `nil` uses the cache's `defaultTTL`.
    ///     A zero, negative, or non-finite value stores an entry that never
    ///     expires on its own (it can still be purged by iOS or evicted by
    ///     ``removeAll()``).
    /// - Throws: An encoding error if `value` cannot be encoded, or a write
    ///   error if the file cannot be written.
    func store<V: Encodable & Sendable>(_ value: V, for key: String, ttl: TimeInterval? = nil) throws {
        let now = Date()
        let lifetime = ttl ?? defaultTTL
        let expiresAt: Date? = (lifetime.isFinite && lifetime > 0)
            ? now.addingTimeInterval(lifetime)
            : nil

        let envelope = CacheEnvelope(storedAt: now, expiresAt: expiresAt, payload: value)
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL(for: key), options: Self.writeOptions)
    }

    // MARK: - Reading

    /// Loads the value stored under `key`, or `nil` if there is no usable entry.
    ///
    /// Returns `nil` — and deletes the file as a side effect — when the entry
    /// has expired, was written by an incompatible version of this cache, or is
    /// otherwise undecodable. Bad cache data is a miss, never an error.
    ///
    /// - Parameters:
    ///   - type: The type to decode. Must match what was stored.
    ///   - key: The key the value was stored under.
    /// - Returns: The cached value, or `nil` on a miss.
    func load<V: Decodable & Sendable>(_ type: V.Type, for key: String) throws -> V? {
        try loadEntry(type, for: key)?.value
    }

    /// Loads the value under `key` together with its metadata.
    ///
    /// Use this instead of ``load(_:for:)`` when you need to know *how old* the
    /// data is — to show "updated 4 minutes ago", or to apply a freshness
    /// window that differs from the TTL the entry was written with.
    /// ``CachedLoader`` is built on this.
    ///
    /// - Returns: The entry, or `nil` if absent, expired, or unreadable.
    func loadEntry<V: Decodable & Sendable>(_ type: V.Type, for key: String) throws -> CacheEntry<V>? {
        let url = fileURL(for: key)

        // An absent or unreadable file is a miss. `Data(contentsOf:)` throws for
        // a missing file, which is the common path, not an exceptional one.
        guard let data = try? Data(contentsOf: url) else { return nil }

        let envelope: CacheEnvelope<V>
        do {
            envelope = try decoder.decode(CacheEnvelope<V>.self, from: data)
        } catch {
            // Corrupt bytes, or an entry written by an older envelope format.
            // Evict it so the failure is self-healing on the next store instead
            // of a permanent miss that still occupies disk.
            discard(url)
            return nil
        }

        if let expiresAt = envelope.expiresAt, expiresAt <= Date() {
            discard(url)
            return nil
        }

        return CacheEntry(value: envelope.payload,
                          storedAt: envelope.storedAt,
                          expiresAt: envelope.expiresAt)
    }

    // MARK: - Eviction

    /// Removes the entry for `key`, if any. Removing a key that was never
    /// stored is not an error.
    func remove(_ key: String) throws {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Removes every entry in this cache.
    ///
    /// Only files this cache created (matching its own extension) are deleted;
    /// the directory itself is kept so the cache stays usable afterwards.
    /// Call this on sign-out — cached responses for one account must never be
    /// served to the next one.
    func removeAll() throws {
        for url in try entryURLs() {
            try fileManager.removeItem(at: url)
        }
    }

    /// Deletes every entry whose expiry has passed.
    ///
    /// Expired entries are also evicted lazily on read, so this is an
    /// optimisation for disk usage, not a correctness requirement. A good place
    /// to call it is app launch or a background refresh task.
    ///
    /// Only the envelope header is decoded, so this does not need to know the
    /// payload type of any entry.
    func removeExpired() throws {
        let now = Date()
        for url in try entryURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let metadata = try? decoder.decode(CacheEnvelopeMetadata.self, from: data) else {
                // Undecodable header: the entry could never be read back, so it
                // is dead weight regardless of its notional expiry.
                discard(url)
                continue
            }
            if let expiresAt = metadata.expiresAt, expiresAt <= now {
                try fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - Diagnostics

    /// Total bytes this cache currently occupies on disk.
    ///
    /// Reports allocated size (what the file system actually reserves, rounded
    /// up to block size) where available, falling back to logical file size.
    /// Useful for a "Clear cache (12.4 MB)" affordance in settings.
    var diskSizeBytes: Int {
        get throws {
            let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey]
            return try entryURLs().reduce(into: 0) { total, url in
                guard let values = try? url.resourceValues(forKeys: keys) else { return }
                total += values.totalFileAllocatedSize ?? values.fileSize ?? 0
            }
        }
    }

    // MARK: - Paths

    /// Maps a cache key to the file that holds it, by hashing the key.
    ///
    /// The key is **never** used as a filename directly. A caller will
    /// reasonably build keys out of paths and identifiers — `"users/42/avatar"`,
    /// or a server-supplied string — and a raw key can therefore contain `/`,
    /// `..`, a leading `~`, a NUL byte, or simply exceed the 255-byte filename
    /// limit. Concatenating that onto a directory path turns a cache key into a
    /// path-traversal primitive: `store(value, for: "../../Documents/db.sqlite")`
    /// would otherwise overwrite a file outside the cache.
    ///
    /// Hashing with SHA-256 removes the whole class of bug at once. The output
    /// is a fixed 64 hex characters — always a valid, length-safe, traversal-free
    /// filename — and the mapping is deterministic, so the same key always
    /// resolves to the same file. (This is a namespacing hash, not a security
    /// boundary: keys are not secret and the digest is not salted.)
    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appending(path: name, directoryHint: .notDirectory)
            .appendingPathExtension(Self.fileExtension)
    }

    /// Every file in the cache directory that this cache created.
    private func entryURLs() throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return contents.filter { $0.pathExtension == Self.fileExtension }
    }

    /// Best-effort eviction used on the read path. A failure to delete a bad
    /// entry must not turn a cache miss into a thrown error.
    private func discard(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Directory setup

    /// Characters permitted in a cache name. Deliberately an explicit ASCII
    /// allowlist rather than `CharacterSet.alphanumerics`, which would admit
    /// Unicode that normalises differently across file systems.
    private static let allowedNameCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
    )

    private static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 64, name != ".", name != ".." else { return false }
        return name.unicodeScalars.allSatisfy { allowedNameCharacters.contains($0) }
    }

    /// Resolves and creates the cache directory. Static so it can run before
    /// the actor's stored properties are initialised.
    private static func prepareDirectory(name: String,
                                         directory: FileManager.SearchPathDirectory) throws -> URL {
        guard isValidName(name) else { throw DiskCacheError.invalidCacheName(name) }

        let fileManager = FileManager()
        guard let base = fileManager.urls(for: directory, in: .userDomainMask).first else {
            throw DiskCacheError.directoryUnavailable(directory)
        }

        let url = base
            .appending(path: namespace, directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        excludeFromBackup(url)
        return url
    }

    /// Marks the cache directory as excluded from iCloud and iTunes backups.
    ///
    /// Cached server responses are reproducible; letting them inflate a user's
    /// backup (and their iCloud quota) is a bug. `.cachesDirectory` is already
    /// excluded by iOS, so this is belt and braces there — it is load-bearing
    /// when the caller chooses `.documentDirectory` instead.
    ///
    /// Best effort on purpose: the exclusion is an optimisation, and failing to
    /// set it is not a reason to leave the app with no cache at all.
    private static func excludeFromBackup(_ url: URL) {
        let current = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        guard current?.isExcludedFromBackup != true else { return }

        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }
}

// MARK: - Entry

/// A cache hit: the decoded value plus the metadata stored alongside it.
struct CacheEntry<Value: Sendable>: Sendable {
    /// The decoded payload.
    let value: Value
    /// When the entry was written.
    let storedAt: Date
    /// When the entry stops being served, or `nil` if it does not expire.
    let expiresAt: Date?

    /// How long ago the entry was written.
    var age: TimeInterval { Date().timeIntervalSince(storedAt) }
}

// MARK: - Errors

/// Errors thrown while setting up or using a ``DiskCache``.
///
/// Note what is *not* here: there is no "corrupt entry" or "entry expired"
/// case, because neither is an error the caller can act on — both are reported
/// as a cache miss.
enum DiskCacheError: Error, Equatable, Sendable, LocalizedError {
    /// The cache name contained characters that are unsafe in a path component,
    /// was empty, or exceeded 64 bytes.
    case invalidCacheName(String)
    /// The requested search-path directory does not exist on this platform.
    case directoryUnavailable(FileManager.SearchPathDirectory)

    var errorDescription: String? {
        switch self {
        case .invalidCacheName(let name):
            return "Invalid cache name \"\(name)\". Use 1–64 characters from A–Z, a–z, 0–9, '-', '_', '.'."
        case .directoryUnavailable(let directory):
            return "No directory available for search path \(directory.rawValue)."
        }
    }
}

// MARK: - On-disk format

/// The on-disk representation of a cache entry.
///
/// The metadata sits at the top level next to `payload` rather than nested, so
/// ``DiskCache/removeExpired()`` can read expiry out of an entry without
/// knowing its payload type — a keyed container simply ignores the `payload`
/// key it was not asked about.
///
/// `Codable` is declared conditionally and implemented by hand rather than
/// synthesised, which pins the JSON key names. They are part of the on-disk
/// format: renaming a property without renaming its key would silently
/// invalidate every entry already on users' devices.
private struct CacheEnvelope<Payload> {
    let storedAt: Date
    let expiresAt: Date?
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case storedAt
        case expiresAt
        case payload
    }
}

extension CacheEnvelope: Encodable where Payload: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storedAt, forKey: .storedAt)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encode(payload, forKey: .payload)
    }
}

extension CacheEnvelope: Decodable where Payload: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.storedAt = try container.decode(Date.self, forKey: .storedAt)
        self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        self.payload = try container.decode(Payload.self, forKey: .payload)
    }
}

/// The envelope header on its own, for scanning entries whose payload type is
/// unknown at the call site.
private struct CacheEnvelopeMetadata: Decodable {
    let storedAt: Date
    let expiresAt: Date?
}
