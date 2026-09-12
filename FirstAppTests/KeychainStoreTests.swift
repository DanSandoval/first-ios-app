import Foundation
import XCTest
@testable import FirstApp

/// Round-trips against the real Keychain on the simulator.
///
/// Unlike the networking tests there is no fake here: the Keychain is process
/// storage that outlives the test run, which is exactly why every test below
/// uses a service name containing a fresh UUID. Two consequences: a crashed
/// run can never poison the next one, and nothing here can read or clobber
/// whatever the app itself has stored under its own service name.
///
/// If these ever start failing with OSStatus -34018 (errSecMissingEntitlement),
/// the test bundle has lost its host application -- a unit-test bundle needs a
/// TEST_HOST to have a keychain-access-group at all.
final class KeychainStoreTests: XCTestCase {

    private var store: KeychainStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = KeychainStore(service: Self.uniqueService())
    }

    override func tearDownWithError() throws {
        // Even though the service name is unique per test, clean up anyway:
        // the simulator's keychain persists across runs.
        try store?.removeAll()
        store = nil
        try super.tearDownWithError()
    }

    private static func uniqueService() -> String {
        "com.dansandoval.firstiosapp.tests.\(UUID().uuidString)"
    }

    // MARK: - Round trips

    func testDataRoundTrips() throws {
        // Deliberately not valid UTF-8: the data API must not quietly assume
        // text.
        let payload = Data([0x00, 0x01, 0xFE, 0xFF, 0x7F])

        try store.set(payload, for: "token")

        XCTAssertEqual(try store.data(for: "token"), payload)
    }

    func testStringRoundTrips() throws {
        try store.setString("hunter2", for: "password")

        XCTAssertEqual(try store.string(for: "password"), "hunter2")
    }

    func testMultibyteStringsRoundTrip() throws {
        // UTF-8 into Data and back is where a naive implementation using
        // .ascii or a fixed-width count goes wrong.
        let values = [
            "🔐 keys & café",
            "日本語のトークン",
            "Åström–Ω",
            "emoji sandwich 👨‍👩‍👧‍👦 with a ZWJ family"
        ]

        for (index, value) in values.enumerated() {
            let key = "multibyte-\(index)"
            try store.setString(value, for: key)
            XCTAssertEqual(try store.string(for: key), value, "Failed to round-trip \(value)")
        }
    }

    func testSetOverwritesAnExistingValue() throws {
        try store.setString("first", for: "token")
        try store.setString("second", for: "token")

        // SecItemAdd on an existing item returns errSecDuplicateItem, so an
        // update has to be an explicit SecItemUpdate (or delete-then-add).
        XCTAssertEqual(try store.string(for: "token"), "second")
    }

    // MARK: - Absence

    func testMissingKeyReturnsNilRatherThanThrowing() throws {
        // errSecItemNotFound is an expected outcome, not a failure. Throwing
        // here would force every read site into a do/catch that means "no".
        XCTAssertNil(try store.data(for: "never-stored"))
        XCTAssertNil(try store.string(for: "never-stored"))
    }

    func testContainsReflectsPresence() throws {
        XCTAssertFalse(store.contains("token"))

        try store.setString("v", for: "token")
        XCTAssertTrue(store.contains("token"))

        try store.remove("token")
        XCTAssertFalse(store.contains("token"))
    }

    func testRemovingSomethingThatWasNeverStoredIsNotAnError() {
        // Otherwise every sign-out path needs a contains() check first.
        XCTAssertNoThrow(try store.remove("never-stored"))
    }

    // MARK: - Bulk removal and isolation

    func testRemoveAllClearsEveryKeyForTheService() throws {
        try store.setString("a", for: "one")
        try store.setString("b", for: "two")
        try store.set(Data([0xAB]), for: "three")

        try store.removeAll()

        XCTAssertNil(try store.string(for: "one"))
        XCTAssertNil(try store.string(for: "two"))
        XCTAssertNil(try store.data(for: "three"))
        XCTAssertFalse(store.contains("one"))
    }

    func testRemoveAllOnAnEmptyStoreIsNotAnError() {
        XCTAssertNoThrow(try store.removeAll())
    }

    func testStoresWithDifferentServicesAreIsolated() throws {
        let other = KeychainStore(service: Self.uniqueService())
        defer { try? other.removeAll() }

        try store.setString("mine", for: "token")
        try other.setString("theirs", for: "token")

        XCTAssertEqual(try store.string(for: "token"), "mine")
        XCTAssertEqual(try other.string(for: "token"), "theirs")

        try other.removeAll()
        XCTAssertEqual(try store.string(for: "token"), "mine", "removeAll() must be service-scoped")
    }
}
