import Foundation
import os

/// A thin wrapper over `OSSignposter` for measuring how long things take.
///
/// Signposts are not logs. They are near-zero-cost markers that Instruments
/// turns into a timeline: each interval becomes a labelled bar on the
/// **os_signpost** track, with the duration, count and statistics worked out for
/// you. When a signpost's subsystem is not being recorded, emitting one is
/// close to free, so measured code can stay measured in shipping builds.
///
/// ## Viewing the results
///
/// 1. Xcode ▸ Product ▸ Profile (⌘I) to launch Instruments against the app.
/// 2. Choose the **Time Profiler** template (or **Blank** and add instruments).
/// 3. Click **+** in the toolbar, add the **os_signpost** instrument.
/// 4. Record, exercise the app, stop.
/// 5. In the os_signpost track, expand the subsystem, then the `Performance`
///    category. Each ``measure(_:_:)`` name appears as its own lane.
/// 6. Select the lane and open the detail pane ▸ **Intervals** for every
///    occurrence, or **Summary: Intervals** for count, min, max, average and
///    standard deviation — usually the more useful of the two.
///
/// From the command line, `xctrace record --template 'Time Profiler'` captures
/// the same data into a `.trace` bundle.
///
/// ## Why the names must be `StaticString`
///
/// This trips up nearly everyone on first use:
///
/// ```swift
/// trace.measure("Fetch repositories") { … }   // ✅ a literal is a StaticString
///
/// let name = "Fetch \(repo.owner)"
/// trace.measure(name) { … }                   // ❌ won't compile
/// ```
///
/// The signpost API takes `StaticString` because the name has to be known at
/// compile time — it is stored once in the binary and referenced by pointer, so
/// that emitting a signpost costs a pointer write rather than a string
/// allocation. That constraint is the whole reason signposts are cheap enough to
/// leave in shipping code, and it is not something a wrapper can paper over.
///
/// Dynamic detail belongs in the *message*, which is a normal log message with
/// the usual `Logger` privacy rules — so run anything user-derived through
/// ``Redact`` before putting it there.
///
/// ## Usage
///
/// ```swift
/// let trace = PerfTrace()
///
/// let repositories = try await trace.measure("Fetch repositories") {
///     try await client.send(RepositoriesEndpoint())
/// }
/// ```
///
/// The type is a `Sendable` value wrapping an `OSSignposter`, so one instance
/// can be shared across tasks and actors.
struct PerfTrace: Sendable {

    /// The underlying emitter.
    private let signposter: OSSignposter

    /// Creates a tracer.
    ///
    /// - Parameters:
    ///   - subsystem: Reverse-DNS subsystem, defaulting to ``AppLog/subsystem``
    ///     so signposts line up with this app's log lines in Instruments.
    ///   - category: The Instruments lane these intervals group under.
    init(subsystem: String = AppLog.subsystem, category: String = "Performance") {
        self.signposter = OSSignposter(subsystem: subsystem, category: category)
    }

    /// Whether anything is currently recording these signposts.
    ///
    /// Check this before doing work that exists *only* to produce a signpost
    /// message. The signpost calls themselves already short-circuit, so there is
    /// no need to guard ordinary ``measure(_:_:)`` calls with it.
    var isEnabled: Bool { signposter.signpostsEnabled }

    // MARK: - Intervals

    /// Measures an asynchronous operation as one interval.
    ///
    /// The interval is closed in a `defer`, so it is emitted whether `work`
    /// returns, throws, or the surrounding task is cancelled — an un-ended
    /// interval shows in Instruments as a bar running to the end of the trace,
    /// which is both wrong and hard to miss.
    ///
    /// - Parameters:
    ///   - name: The lane name in Instruments. Must be a literal; see the
    ///     type-level discussion of `StaticString`.
    ///   - work: The operation to time.
    /// - Returns: Whatever `work` returned.
    /// - Throws: Whatever `work` threw, unchanged.
    func measure<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        // A fresh ID per call rather than the default `.exclusive`, so that two
        // overlapping runs of the same operation — the normal case with
        // concurrent requests — are matched up as two separate intervals
        // instead of being nested and mis-paired.
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }

        return try await work()
    }

    /// Measures a synchronous operation as one interval.
    ///
    /// The synchronous counterpart to ``measure(_:_:)``, for work that never
    /// suspends: a JSON decode, a Keychain round trip, a layout pass.
    ///
    /// - Parameters:
    ///   - name: The lane name in Instruments. Must be a literal.
    ///   - work: The operation to time.
    /// - Returns: Whatever `work` returned.
    /// - Throws: Whatever `work` threw, unchanged.
    func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }

        return try work()
    }

    // MARK: - Events

    /// Emits a zero-length marker at the current instant.
    ///
    /// Use this for things that happen rather than things that take time — a
    /// cache miss, a retry, a token refresh. In Instruments these appear as
    /// points on the track, handy for lining a spike in one instrument up
    /// against a moment in the app's own logic.
    ///
    /// - Parameter name: The event name. Must be a literal.
    func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
