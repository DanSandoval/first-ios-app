import Foundation
import Security

/// A small, dependency-free wrapper over the iOS Keychain for storing secrets
/// belonging to a single *service* (a namespace you choose, conventionally your
/// bundle identifier plus a suffix).
///
/// Every item is stored as a generic password keyed on
/// `kSecAttrService` (this instance's ``service``) + `kSecAttrAccount` (the key
/// you pass in), so two `KeychainStore` values with different services never
/// see each other's items.
///
/// The type is a `Sendable` value holding nothing but a `String`, and the
/// underlying Security framework calls are themselves thread-safe, so an
/// instance can be shared freely across tasks and actors.
///
/// - Important: This type never logs, prints, or otherwise emits the values it
///   stores. Secrets must not end up in the console, in `os_log`, or in crash
///   reports — keep it that way when extending this file.
struct KeychainStore: Sendable {

    /// The `kSecAttrService` namespace all of this store's items live under.
    let service: String

    /// Creates a store scoped to `service`.
    ///
    /// - Parameter service: The namespace for every item written through this
    ///   instance. Use a reverse-DNS string, e.g.
    ///   `"com.example.myapp.tokens"`. Anything else sharing this exact string
    ///   shares the same items.
    init(service: String) {
        self.service = service
    }

    // MARK: - Data

    /// Writes `data` for `key`, replacing any existing value.
    ///
    /// The write is an upsert: it attempts `SecItemAdd` first and falls back to
    /// `SecItemUpdate` when the item already exists.
    ///
    /// - Parameters:
    ///   - data: The secret bytes to store.
    ///   - key: The `kSecAttrAccount` identifier for the item.
    /// - Throws: ``KeychainError/unexpectedStatus(_:)`` if the Security
    ///   framework reports a failure.
    func set(_ data: Data, for key: String) throws {
        var addQuery = baseQuery(for: key)
        addQuery[kSecValueData as String] = data
        // Accessibility is only meaningful at insert time; it is set here rather
        // than in `baseQuery` because including it in a *search* query would
        // filter results instead of describing them.
        //
        // `AfterFirstUnlock` — readable once the user has unlocked the device at
        // least once since boot, so background work (refreshes, notifications,
        // BGTask handlers) can still authenticate while the screen is locked.
        // The stricter `WhenUnlocked` would make those reads fail silently.
        //
        // `ThisDeviceOnly` — excludes the item from iCloud Keychain *and from
        // encrypted device backups*. That backup exclusion is the important half:
        // without it the secret rides along into an iTunes/Finder backup and is
        // restored onto a different device, which is exactly how a token ends up
        // somewhere its owner never authorised.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return

        case errSecDuplicateItem:
            // Update in place rather than delete-then-add. A delete/add pair
            // leaves a window in which the secret is absent from the Keychain:
            // if the process is killed (or a concurrent reader runs) between the
            // two calls, the credential is simply gone.
            // Re-assert accessibility on update, not only on insert. An item
            // written by an earlier build under a weaker class (WhenUnlocked,
            // or one lacking ThisDeviceOnly and so syncing to iCloud) would
            // otherwise keep that class forever and the upsert would silently
            // tighten nothing.
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(
                baseQuery(for: key) as CFDictionary,
                attributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }

        default:
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    /// Reads the data stored for `key`.
    ///
    /// - Parameter key: The `kSecAttrAccount` identifier for the item.
    /// - Returns: The stored bytes, or `nil` when no such item exists. A missing
    ///   item is a normal result, not an error.
    /// - Throws: ``KeychainError/unexpectedStatus(_:)`` for any other Security
    ///   framework failure, or ``KeychainError/invalidData`` if the item exists
    ///   but did not come back as data.
    func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            // A conditional cast rather than a force-cast: an item written by
            // other code under the same service could in principle be a
            // different shape, and that is a data problem, not a crash.
            guard let data = result as? Data else {
                throw KeychainError.invalidData
            }
            return data

        case errSecItemNotFound:
            return nil

        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Strings

    /// Writes `value` for `key` as UTF-8, replacing any existing value.
    ///
    /// - Throws: ``KeychainError/invalidData`` if `value` cannot be encoded as
    ///   UTF-8, or ``KeychainError/unexpectedStatus(_:)`` on a Keychain failure.
    func setString(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try set(data, for: key)
    }

    /// Reads the string stored for `key`, decoding it as UTF-8.
    ///
    /// - Returns: The stored string, or `nil` when no such item exists.
    /// - Throws: ``KeychainError/invalidData`` if the stored bytes are not valid
    ///   UTF-8, or ``KeychainError/unexpectedStatus(_:)`` on a Keychain failure.
    func string(for key: String) throws -> String? {
        guard let data = try data(for: key) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    // MARK: - Removal

    /// Deletes the item stored for `key`.
    ///
    /// Deleting something that is not there is a success, so this is safe to
    /// call unconditionally (e.g. from a "sign out" path that may run twice).
    ///
    /// - Throws: ``KeychainError/unexpectedStatus(_:)`` on a Keychain failure
    ///   other than "not found".
    func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Deletes **every** generic-password item under this store's ``service``.
    ///
    /// - Warning: The blast radius is the whole service namespace, including
    ///   items written by other code that happens to use the same service
    ///   string. Scope your services narrowly if you intend to call this.
    /// - Throws: ``KeychainError/unexpectedStatus(_:)`` on a Keychain failure
    ///   other than "not found".
    func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Existence

    /// Reports whether an item exists for `key`, without reading its value.
    ///
    /// Deliberately non-throwing: callers use this for cheap UI decisions
    /// ("is the user signed in?"), where a Keychain failure and a missing item
    /// lead to the same behaviour. Use ``data(for:)`` or ``string(for:)`` when
    /// you need to distinguish the two.
    func contains(_ key: String) -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Private

    /// The attributes that identify a single item: the class, this store's
    /// service, and the caller's key.
    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // Opt in to the modern, file-data-protection-backed keychain rather
            // than the legacy file-based one. This keeps behaviour identical
            // across platforms and is required for keychain access on macOS
            // targets built from the same source.
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}

/// Errors thrown by ``KeychainStore``.
enum KeychainError: Error, Equatable, LocalizedError {

    /// The Security framework returned a status other than `errSecSuccess`.
    ///
    /// The associated `OSStatus` is the raw code (see `SecBase.h`), useful for
    /// diagnostics; it never carries any part of the secret itself.
    case unexpectedStatus(OSStatus)

    /// A value could not be converted between `Data` and `String` as UTF-8, or
    /// an item came back in an unexpected shape.
    case invalidData

    /// A human-readable description, safe to show in UI or write to a log.
    ///
    /// Only the status code and Apple's own description of it are included —
    /// never the stored value.
    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error \(status): \(message)"
            }
            // Some statuses have no registered message; the bare code still
            // tells a reader (or a bug report) what happened.
            return "Keychain error \(status)."

        case .invalidData:
            return "The stored value was not in the expected format."
        }
    }
}
