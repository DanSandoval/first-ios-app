import Foundation
import UIKit

/// One vocabulary for every permission the system can grant.
///
/// Camera, photo library, location, notifications, contacts, calendars,
/// microphone and biometrics each ship their own authorization enum, with
/// different case names for the same five ideas and different spellings of
/// "ask". Translating each of them into this type at the edge means the rest of
/// the app — view models, gating logic, tests — speaks one language, and adding
/// a sixth capability does not add a sixth switch to the UI layer.
///
/// ## Mapping the system enums
///
/// The mappings are mechanical. Written out here rather than implemented, so
/// this file pulls in no capability frameworks:
///
/// | System value                                         | `PermissionStatus`    |
/// |------------------------------------------------------|-----------------------|
/// | `AVAuthorizationStatus.notDetermined`                | ``notDetermined``     |
/// | `AVAuthorizationStatus.denied`                       | ``denied``            |
/// | `AVAuthorizationStatus.restricted`                   | ``restricted``        |
/// | `AVAuthorizationStatus.authorized`                   | ``granted``           |
/// | `PHAuthorizationStatus.limited`                      | ``limited``           |
/// | `CLAuthorizationStatus.authorizedWhenInUse`/`Always` | ``granted``           |
/// | `UNAuthorizationStatus.provisional`                  | ``limited``           |
/// | `UNAuthorizationStatus.ephemeral`                    | ``limited``           |
///
/// Location's two "authorized" cases collapse to ``granted`` on purpose: the
/// when-in-use versus always distinction is a *scope* question, not a
/// permission-state question, and the screen asking "may I use location at all"
/// should not have to care.
enum PermissionStatus: Sendable, Equatable {

    /// The user has not been asked yet. The only state in which prompting is
    /// allowed — the system silently denies a second prompt.
    case notDetermined

    /// The user was asked and said no, or later revoked access in Settings.
    /// Recoverable only through Settings; see ``openAppSettings()``.
    case denied

    /// Access is blocked by something the user does not control — Screen Time,
    /// parental controls, or an MDM profile on a managed device. Prompting is
    /// pointless and so is sending them to Settings; the switch is not there.
    case restricted

    /// Full access.
    case granted

    /// Partial access: a chosen subset of the photo library, or provisional
    /// (quiet) notification delivery. Usable, but not everything is visible —
    /// treat it as success and offer a way to widen the selection.
    case limited
}

// MARK: - Decisions

extension PermissionStatus {

    /// Whether the capability can be used right now.
    ///
    /// ``limited`` counts. A user who granted access to twelve photos granted
    /// access; an app that treats that as a denial and re-prompts is the reason
    /// the limited option exists.
    var isUsable: Bool {
        switch self {
        case .granted, .limited:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        }
    }

    /// Whether asking the system for access could still produce a prompt.
    ///
    /// Only ``notDetermined``. Calling `request()` in any other state returns
    /// the existing answer without showing anything — which is what produces
    /// the classic bug of a button that silently does nothing.
    var canPrompt: Bool {
        self == .notDetermined
    }

    /// Whether the user can fix this themselves, and the only place they can.
    ///
    /// True for ``denied`` alone. ``restricted`` is deliberately excluded: the
    /// toggle is absent under a restriction profile, so routing someone to
    /// Settings sends them to look for a control that is not there.
    var requiresSettingsTrip: Bool {
        self == .denied
    }
}

// MARK: - Requesting

/// A capability that can report and request its own authorization.
///
/// Conform one small type per capability — `CameraPermission`,
/// `PhotoLibraryPermission`, `NotificationPermission` — and the UI can gate on
/// any of them through the same two calls.
///
/// ```swift
/// struct CameraPermission: PermissionRequesting {
///     var status: PermissionStatus {
///         get async { PermissionStatus(AVCaptureDevice.authorizationStatus(for: .video)) }
///     }
///
///     func request() async -> PermissionStatus {
///         await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
///     }
/// }
/// ```
///
/// - Important: Every capability that prompts requires a matching usage-string
///   key in `Info.plist` (`NSCameraUsageDescription`,
///   `NSPhotoLibraryUsageDescription`, `NSLocationWhenInUseUsageDescription`,
///   and so on). A missing key is not a warning — the app is terminated the
///   moment the prompt would appear.
protocol PermissionRequesting: Sendable {

    /// The current authorization, without prompting.
    ///
    /// `async` because several of the system APIs behind it are
    /// (`UNUserNotificationCenter.notificationSettings()`, for one).
    var status: PermissionStatus { get async }

    /// Prompts if — and only if — the status is ``PermissionStatus/notDetermined``,
    /// and returns the resulting status.
    ///
    /// Returns the existing status unchanged in every other case. Callers should
    /// check ``PermissionStatus/requiresSettingsTrip`` on the result rather than
    /// assuming a non-granted return means the user just now said no.
    func request() async -> PermissionStatus
}

// MARK: - Settings

/// Opens this app's page in the Settings app.
///
/// Once a permission is ``PermissionStatus/denied``, **this is the only route
/// back**. The system will not show the prompt a second time, no matter how
/// many times the app asks, and `request()` returns the denial immediately and
/// silently. An app that has no path to Settings has a dead end: the user taps
/// "Enable Camera", nothing happens, and there is nowhere for them to go.
///
/// This is the single most commonly missed step in a permission flow. Pair it
/// with text that says what to tap, because the app cannot deep-link to the
/// individual switch — only to its own settings page:
///
/// ```swift
/// if status.requiresSettingsTrip {
///     VStack {
///         Text("Camera access is off. Turn it on in Settings › Camera.")
///         Button("Open Settings") { Task { await openAppSettings() } }
///     }
/// }
/// ```
///
/// - Returns: `false` if the URL could not be opened, which in practice means
///   the app is running somewhere that has no Settings app to open (an app
///   extension, or a test host). Show the instructions as plain text in that
///   case rather than a button that does nothing.
@MainActor
@discardableResult
func openAppSettings() async -> Bool {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
    return await UIApplication.shared.open(url, options: [:])
}
