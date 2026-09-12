import Foundation
import UIKit

/// Read-only facts about the device and app build.
///
/// Deliberately avoids `UIScreen.main` (soft-deprecated under multi-scene);
/// callers measure available size with `GeometryReader` instead.
enum DeviceInfo {

    /// Marketing device class, e.g. "iPhone" or "iPad".
    static var model: String {
        UIDevice.current.model
    }

    /// Hardware identifier, e.g. "iPhone15,2".
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    /// Operating system name, e.g. "iOS".
    static var systemName: String {
        UIDevice.current.systemName
    }

    /// Operating system version, e.g. "17.4".
    static var systemVersion: String {
        UIDevice.current.systemVersion
    }

    /// Short version plus build number, formatted as "1.0 (1)".
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (short, build) {
        case let (short?, build?):
            return "\(short) (\(build))"
        case let (short?, nil):
            return short
        case let (nil, build?):
            return "(\(build))"
        default:
            return "Unknown"
        }
    }
}
