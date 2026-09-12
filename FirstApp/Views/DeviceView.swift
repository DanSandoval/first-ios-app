import SwiftUI

/// The third tab: the parts of an app that only make sense on real hardware,
/// plus storage that outlives the process.
struct DeviceView: View {
    @State private var viewSize: CGSize = .zero

    // @AppStorage reads and writes UserDefaults, which is a file on disk in the
    // app's container — so these two values survive a force-quit.
    @AppStorage(StorageKey.launchCount) private var launchCount = 0
    @AppStorage(StorageKey.nickname) private var nickname = ""

    var body: some View {
        NavigationStack {
            Form {
                hapticsSection
                deviceSection
                persistenceSection
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear { viewSize = proxy.size }
                }
            )
            .navigationTitle("Device")
        }
    }

    private var hapticsSection: some View {
        Section {
            Button("Light tap") { Haptics.impact(.light) }
            Button("Medium tap") { Haptics.impact(.medium) }
            Button("Heavy tap") { Haptics.impact(.heavy) }
            Button("Success notification") { Haptics.notify(.success) }
        } header: {
            Text("Haptics")
        } footer: {
            Text("Haptics come from the Taptic Engine, which is hardware. These buttons do nothing in the Simulator — run the app on a real iPhone to feel them.")
        }
    }

    private var deviceSection: some View {
        Section {
            row("Model", DeviceInfo.model)
            row("Identifier", DeviceInfo.modelIdentifier, monospaced: true)
            row("System", "\(DeviceInfo.systemName) \(DeviceInfo.systemVersion)")
            row("App version", DeviceInfo.appVersion, monospaced: true)
            row("View size", "\(Int(viewSize.width)) × \(Int(viewSize.height)) pt")
        } header: {
            Text("This device")
        } footer: {
            Text("Sizes are in points, not pixels. A point maps to two or three pixels depending on the screen, which is why you lay out in points and let iOS scale.")
        }
    }

    private var persistenceSection: some View {
        Section {
            row("Launches", "\(launchCount)")

            HStack {
                Text("Nickname")
                Spacer()
                TextField("Optional", text: $nickname)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
        } header: {
            Text("Persistence")
        } footer: {
            Text("Force-quit the app from the app switcher and open it again. The launch count goes up by one and your nickname is still here, because @AppStorage writes both to UserDefaults instead of keeping them in memory.")
        }
    }

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(monospaced ? .body.monospaced() : .body)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DeviceView()
}
