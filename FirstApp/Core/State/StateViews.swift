import SwiftUI

// Reusable full-screen views for the non-`loaded` cases of ``Loadable``.
//
// All three fill the space they are given and paint a semantic background, so
// they can be dropped straight into a `switch` in a screen's `body` without the
// layout jumping between states. Colours are semantic only — `.secondary`,
// `.tint`, `Color(.systemGroupedBackground)` — so dark mode and increased
// contrast work without a second code path.

/// A centred progress indicator with a caption, for ``Loadable/loading``.
struct LoadingStateView: View {

    private let message: String

    /// Creates a loading view.
    ///
    /// - Parameter message: The caption below the spinner. Keep it specific
    ///   ("Loading repositories…") where you can; the default is a fallback.
    init(message: String = "Loading…") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        // One announcement ("Loading repositories") instead of VoiceOver
        // reading the indeterminate progress indicator and the label separately.
        .accessibilityElement(children: .combine)
    }
}

/// A "nothing here" placeholder, for ``Loadable/empty``.
///
/// Built on `ContentUnavailableView` so it inherits the system's metrics,
/// Dynamic Type behaviour, and future platform restyling for free.
struct EmptyStateView: View {

    private let title: String
    private let message: String
    private let systemImage: String

    /// Creates an empty-state view.
    ///
    /// - Parameters:
    ///   - title: A short headline, e.g. `"No Repositories"`.
    ///   - message: One sentence explaining why the screen is empty and what
    ///     the reader can do about it.
    ///   - systemImage: An SF Symbol name for the icon.
    init(title: String, message: String, systemImage: String) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// A failure placeholder with an optional retry action, for
/// ``Loadable/failed(_:)``.
struct ErrorStateView: View {

    private let error: APIError
    private let retry: (() -> Void)?

    /// Creates an error view.
    ///
    /// - Parameters:
    ///   - error: The failure to describe. Its `localizedDescription` is shown,
    ///     so `APIError` is responsible for keeping that message user-facing.
    ///   - retry: An action for the "Try Again" button. Pass `nil` — the
    ///     default — for failures that retrying cannot fix (a bad token, a
    ///     malformed response), so the reader is not invited to hammer a button
    ///     that will fail identically.
    init(error: APIError, retry: (() -> Void)? = nil) {
        self.error = error
        self.retry = retry
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                // A text style rather than a fixed point size, so the icon
                // scales with Dynamic Type alongside the labels.
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Something Went Wrong")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let retry {
                Button("Try Again", action: retry)
                    // `.borderedProminent` already draws itself in the app's
                    // tint, so no colour is specified here.
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
