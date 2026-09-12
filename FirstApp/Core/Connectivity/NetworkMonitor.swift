import Foundation
import Network
import Observation

/// Live view of the device's network path.
///
/// ## What this does and does not tell you
///
/// `NWPathMonitor` reports **path availability, not reachability of your
/// server**. A device joined to a captive-portal Wi-Fi network — a hotel, an
/// airport, a coffee shop — reports a perfectly satisfied Wi-Fi path while
/// every request you make is silently swallowed by the portal. VPN
/// disconnections, DNS failures and a server that is simply down all look
/// "connected" here too.
///
/// So do not use this to *predict* whether a request will succeed. The honest
/// pattern is the other way round: let the request run, let it fail, and use
/// this to *explain* the failure ("You appear to be offline") and to decide
/// whether retrying is worth attempting. Anything else produces an app that
/// refuses to try on a connection that would have worked.
///
/// ## Usage
///
/// ```swift
/// @main struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             RootView()
///                 .task { NetworkMonitor.shared.start() }
///                 .offlineBanner()
///         }
///     }
/// }
/// ```
///
/// Reading any property from a SwiftUI `body` registers the view for updates
/// automatically — `@Observable` needs no property wrapper at the call site.
///
/// - Note: This is a singleton by design. One `NWPathMonitor` per process is
///   all the system needs, and a second one costs a thread hop per path change
///   for information you already have. `start()` and `stop()` exist for
///   lifecycle control; there is no second instance to create.
@Observable
@MainActor
final class NetworkMonitor {

    /// The process-wide monitor. Call ``start()`` once, early.
    static let shared = NetworkMonitor()

    // MARK: - Published state

    /// Whether a usable network path currently exists.
    ///
    /// `true` for `NWPath.Status.satisfied` only. A `.requiresConnection` path
    /// — a VPN configured to connect on demand, for instance — reports `false`
    /// here, because nothing will flow until something triggers it.
    ///
    /// Defaults to `true` before the first path update arrives. That is
    /// deliberate: assuming "offline" until proven otherwise makes every launch
    /// flash an offline banner for the few milliseconds before the first
    /// callback lands.
    ///
    /// Remember that this is path availability, not server reachability — see
    /// the type-level discussion above.
    private(set) var isConnected: Bool = true

    /// Whether the current path costs the user money or battery to use.
    ///
    /// `true` on cellular and on a personal hotspot (where the *other* device
    /// is paying for the data). Respecting this is the difference between an
    /// app that is polite about someone's data plan and one that is not:
    /// prefetching a feed of images, syncing a backup, or auto-playing video
    /// over an expensive path is the behaviour that gets an app deleted after
    /// a bill arrives.
    ///
    /// Defer discretionary work while this is `true`; never defer work the user
    /// explicitly asked for.
    private(set) var isExpensive: Bool = false

    /// Whether the user has asked the system to conserve data on this path.
    ///
    /// `true` when **Low Data Mode** is enabled for the current Wi-Fi network
    /// or cellular plan. Unlike ``isExpensive``, this is not an inference about
    /// cost — it is an explicit instruction from the person using the device,
    /// and it should be treated as one: no prefetching, no speculative
    /// requests, no background refresh, lower-resolution assets.
    ///
    /// `URLSession` honours this for you when a request sets
    /// `allowsConstrainedNetworkAccess = false`; this flag is for the decisions
    /// the framework cannot make on your behalf.
    private(set) var isConstrained: Bool = false

    /// The interface carrying the current path.
    ///
    /// Defaults to ``ConnectionType/other`` before the first update: the type
    /// is genuinely unknown at that point, and reporting ``ConnectionType/none``
    /// would contradict ``isConnected``.
    private(set) var connectionType: ConnectionType = .other

    /// The kind of interface a path is running over.
    enum ConnectionType: Sendable {

        /// Wi-Fi, including a Wi-Fi personal hotspot (also ``isExpensive``).
        case wifi

        /// A cellular radio.
        case cellular

        /// Wired Ethernet, including USB-C and Thunderbolt adapters on iPad.
        case wired

        /// A satisfied path over some other interface — a loopback or a virtual
        /// interface — or one whose type has not been reported yet.
        case other

        /// No usable path.
        case none
    }

    // MARK: - Lifecycle

    /// Queue the path callbacks are delivered on.
    ///
    /// `NWPathMonitor` requires a queue that is not the main queue; updates are
    /// snapshotted here and republished on the main actor.
    private let queue = DispatchQueue(label: "NetworkMonitor.pathUpdates", qos: .utility)

    /// Non-`nil` exactly while monitoring. Doubles as the idempotency guard for
    /// ``start()``. Not observable — no view has any business redrawing because
    /// monitoring started.
    @ObservationIgnored private var monitor: NWPathMonitor?

    private init() {}

    /// Begins monitoring. Safe to call repeatedly.
    ///
    /// A second call while already running is a no-op rather than a second
    /// monitor: starting from both an app-level `.task` and a view modifier is
    /// a normal thing to do, and leaking a monitor per call would mean a
    /// redundant thread hop on every path change for the life of the process.
    func start() {
        guard monitor == nil else { return }

        let monitor = NWPathMonitor()
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            // Flatten the path into Sendable primitives *here*, on the monitor's
            // own queue, so nothing framework-owned crosses the actor boundary.
            let snapshot = NetworkPathSnapshot(path)
            Task { @MainActor in
                self?.apply(snapshot)
            }
        }

        monitor.start(queue: queue)
    }

    /// Stops monitoring and releases the underlying monitor.
    ///
    /// The last published values are left in place rather than reset: they
    /// describe the last thing that was actually true, and zeroing them would
    /// make every observing view redraw with a fabricated "offline" state.
    ///
    /// There is no need to call this on backgrounding — the system suspends
    /// the callbacks with the process, and a monitor that was stopped cannot
    /// report the path change that happened while the app was away.
    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    // MARK: - Publishing

    /// Applies a snapshot, touching only the properties that actually changed
    /// so observers are not woken for a no-op update.
    private func apply(_ snapshot: NetworkPathSnapshot) {
        let type: ConnectionType
        if !snapshot.isConnected {
            type = .none
        } else if snapshot.usesWiFi {
            // Ordered by what the user would call the connection: a device on
            // Wi-Fi with cellular also up is "on Wi-Fi".
            type = .wifi
        } else if snapshot.usesCellular {
            type = .cellular
        } else if snapshot.usesWiredEthernet {
            type = .wired
        } else {
            type = .other
        }

        if isConnected != snapshot.isConnected { isConnected = snapshot.isConnected }
        if isExpensive != snapshot.isExpensive { isExpensive = snapshot.isExpensive }
        if isConstrained != snapshot.isConstrained { isConstrained = snapshot.isConstrained }
        if connectionType != type { connectionType = type }
    }
}

// MARK: - Path snapshot

/// The facts we publish, extracted from an `NWPath` on the monitor's queue.
///
/// Declared at file scope, and carrying nothing but `Bool`s, so that building
/// one is unambiguously safe off the main actor: an `NWPath` is framework-owned
/// state that should not outlive the callback, and ``NetworkMonitor``'s own
/// nested types are main-actor territory. The interpretation — which of these
/// flags means "Wi-Fi" — happens on the actor, in
/// ``NetworkMonitor/apply(_:)``.
private struct NetworkPathSnapshot: Sendable {
    let isConnected: Bool
    let isExpensive: Bool
    let isConstrained: Bool
    let usesWiFi: Bool
    let usesCellular: Bool
    let usesWiredEthernet: Bool

    init(_ path: NWPath) {
        let satisfied = path.status == .satisfied

        self.isConnected = satisfied
        self.isExpensive = path.isExpensive
        self.isConstrained = path.isConstrained

        // An unsatisfied path can still report interfaces it *would* use; only
        // trust these when there is actually a path.
        self.usesWiFi = satisfied && path.usesInterfaceType(.wifi)
        self.usesCellular = satisfied && path.usesInterfaceType(.cellular)
        self.usesWiredEthernet = satisfied && path.usesInterfaceType(.wiredEthernet)
    }
}
