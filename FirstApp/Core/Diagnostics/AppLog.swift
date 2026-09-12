import Foundation
import os

/// The app's `Logger` instances, one per area of the codebase.
///
/// Every log line in the app should go through one of these rather than through
/// `print(_:)` or a freshly constructed `Logger`. Two reasons: `print` writes to
/// stdout, which nothing captures on a real device, and a shared set of
/// categories is what makes the log *filterable* once you are staring at a
/// sysdiagnose from a user's phone.
///
/// ## Choosing a category
///
/// - ``networking`` — requests, responses, retries, transport failures.
/// - ``security`` — Keychain reads/writes, token presence, auth state changes.
/// - ``persistence`` — disk and database reads/writes, cache hits and misses.
/// - ``ui`` — view lifecycle, navigation, user-driven state changes.
/// - ``lifecycle`` — app launch, scene phase, background tasks.
///
/// ## Reading these logs
///
/// **Console.app** (Window ▸ Devices, pick the device, Start streaming): put
/// this in the search field and choose "Subsystem" from the dropdown:
///
/// ```
/// com.dansandoval.firstiosapp
/// ```
///
/// then add a second filter on "Category" for e.g. `Networking`. Turn on
/// Action ▸ Include Debug Messages and Include Info Messages — **`.debug` and
/// `.info` are hidden by default**, which is the usual reason a log line you
/// know you wrote appears to be missing.
///
/// **Terminal**, against a connected device or the simulator:
///
/// ```sh
/// # Live stream, one category, including debug-level lines.
/// log stream --level debug \
///   --predicate 'subsystem == "com.dansandoval.firstiosapp" AND category == "Networking"'
///
/// # Everything the app logged in the last 10 minutes, after the fact.
/// log show --last 10m --info --debug \
///   --predicate 'subsystem == "com.dansandoval.firstiosapp"'
/// ```
///
/// ## Privacy: the single most important thing in this file
///
/// `Logger`'s string interpolation is **private by default for any non-literal
/// value**. Given `logger.debug("token: \(token)")`, the literal `"token: "` is
/// always visible, but `token` is redacted to `<private>` when the log is read
/// anywhere outside a debugger — Console.app on another machine, a sysdiagnose
/// bundle, a crash report, `log show` on the user's Mac.
///
/// ```swift
/// logger.debug("Fetched \(url)")                    // url → <private>
/// logger.debug("Fetched \(url, privacy: .public)")  // url → printed in full
/// ```
///
/// That default is a **feature, not an obstacle**. The rule for this codebase:
///
/// > Mark a value `.public` only when you are certain it is not sensitive.
///
/// "Certain" means certain about every value the expression can ever produce,
/// not just the one in front of you today. A status code is certainly fine. A
/// URL is not — query strings carry tokens. A header value is not. An error's
/// `localizedDescription` is not, because framework errors embed the failing
/// URL and sometimes the request that produced it.
///
/// Two traps worth knowing:
///
/// - **A debugger attached makes everything look public.** Running from Xcode,
///   `<private>` values print in the clear. Code that looks safe in the
///   simulator can leak on a user's device. Judge privacy by reading the source,
///   never by reading the Xcode console.
/// - **Redaction is not encryption.** `.private` keeps a value out of the log
///   *store*; it does not make logging a secret acceptable. Credentials should
///   never reach a `Logger` at all — run them through ``Redact`` first.
///
/// When you need to correlate a value across lines without revealing it, use
/// the hashed form instead of going public:
///
/// ```swift
/// logger.debug("Session \(sessionID, privacy: .private(mask: .hash))")
/// ```
enum AppLog {

    /// The `subsystem` string shared by every logger here, taken from the main
    /// bundle so that a rename of the app carries through automatically.
    ///
    /// The fallback matters more than it looks: `Bundle.main.bundleIdentifier`
    /// is `nil` in some unit-test and SwiftUI-preview hosts, and a `nil`-derived
    /// empty subsystem produces log lines that no predicate can select.
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.dansandoval.firstiosapp"

    /// HTTP requests, responses, retries and transport failures.
    ///
    /// Prefer ``NetworkLogger`` over calling this directly — it applies
    /// ``Redact`` to URLs and headers for you.
    static let networking = Logger(subsystem: subsystem, category: "Networking")

    /// Keychain access, credential presence, and authentication state changes.
    ///
    /// - Important: Log *facts about* a credential (present/absent, length,
    ///   ``Redact/token(_:)`` fingerprint) — never the credential.
    static let security = Logger(subsystem: subsystem, category: "Security")

    /// Disk, database and cache activity.
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")

    /// View lifecycle, navigation and user-driven state changes.
    static let ui = Logger(subsystem: subsystem, category: "UI")

    /// App launch, scene phase transitions and background task execution.
    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
}
