import SwiftUI

/// Overlays an unobtrusive banner whenever ``NetworkMonitor/isConnected`` is
/// `false`.
///
/// Applied once, at the root of a scene:
///
/// ```swift
/// RootView()
///     .offlineBanner()
/// ```
///
/// The banner is deliberately quiet — a small capsule above the home indicator,
/// in secondary colours, non-interactive. An offline state is information, not
/// an error: a full-screen takeover or a modal alert interrupts work the user
/// can often still do (reading cached content, filling in a form) and cannot be
/// dismissed by anything they are able to do about it.
///
/// It reports path availability, so it can be wrong in the user's favour — see
/// the discussion on ``NetworkMonitor``. That is another reason to keep it to a
/// caption rather than a blocking state.
struct OfflineBannerModifier: ViewModifier {

    /// Honours the system-wide Reduce Motion setting. When on, the banner
    /// cross-fades instead of sliding: Reduce Motion asks for no *movement*,
    /// not for abrupt appearance, and a fade is the documented substitute.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The text shown in the banner, and the VoiceOver label.
    let message: String

    func body(content: Content) -> some View {
        // Read once per evaluation: this is the property that registers the
        // view with Observation, so the body re-runs when the path changes.
        let isConnected = NetworkMonitor.shared.isConnected

        content
            // Idempotent, so applying this modifier does not conflict with an
            // app that also starts the monitor at launch, and re-appearing
            // costs nothing.
            .onAppear { NetworkMonitor.shared.start() }
            .overlay(alignment: .bottom) {
                if !isConnected {
                    OfflineBannerLabel(message: message)
                        .padding(.bottom, 8)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                }
            }
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3),
                value: isConnected
            )
    }
}

// MARK: - Banner

/// The banner itself, separated from the modifier so it can be previewed and
/// reused without having to force the monitor into an offline state.
struct OfflineBannerLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: Capsule(style: .continuous)
            )
            // A thin separator keeps the capsule legible against content of
            // any colour without introducing a colour of its own.
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            // Nothing here is tappable, and the banner sits over real content —
            // it must never swallow a touch meant for what is underneath.
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(message)
    }
}

// MARK: - Call site

extension View {

    /// Shows an offline banner over this view while the device has no network
    /// path, and starts ``NetworkMonitor`` if it is not already running.
    ///
    /// Apply it once per scene, at the root. Applying it to several nested
    /// views stacks several banners.
    ///
    /// - Parameter message: Banner text, also used as the VoiceOver label.
    ///   Keep it to a statement of fact — the user cannot act on it, and
    ///   promising that work "will sync later" is a commitment the banner
    ///   cannot keep.
    func offlineBanner(message: String = "No Internet Connection") -> some View {
        modifier(OfflineBannerModifier(message: message))
    }
}

// MARK: - Preview

#Preview("Offline banner") {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack(spacing: 12) {
            Text("Content")
                .font(.largeTitle.weight(.semibold))
            Text("The banner sits above the home indicator and passes touches through.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
    .overlay(alignment: .bottom) {
        OfflineBannerLabel(message: "No Internet Connection")
            .padding(.bottom, 8)
    }
}
