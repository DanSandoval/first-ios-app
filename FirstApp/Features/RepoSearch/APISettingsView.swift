import SwiftUI

/// Sheet for storing an optional GitHub personal access token in the Keychain.
///
/// The token is write-only from the UI's point of view: it goes in, it is never
/// read back out for display. The only thing this screen ever shows about it is
/// whether one exists.
struct APISettingsView: View {
    private static let tokenSettingsURL = URL(string: "https://github.com/settings/tokens")

    @Bindable var tokenStore: TokenStore

    @Environment(\.dismiss) private var dismiss

    @State private var tokenInput = ""
    @State private var alertMessage: String?

    private var trimmedInput: String {
        tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Without a token, GitHub allows 10 search requests per minute from this device. Adding a personal access token raises that to 30 per minute.")
                    Text("A token used only for searching public repositories needs **no scopes at all**. Leave every checkbox unticked when you create it — granting more access than the app needs is the risk, not the token itself.")
                } header: {
                    Text("Why add a token")
                }

                Section {
                    SecureField("ghp_…", text: $tokenInput)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)

                    Button("Save", action: save)
                        .disabled(trimmedInput.isEmpty)

                    if let tokenSettingsURL = Self.tokenSettingsURL {
                        Link(destination: tokenSettingsURL) {
                            Label("Create a token on GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                } header: {
                    Text("Token")
                } footer: {
                    Text("Stored in the iOS Keychain, not in UserDefaults.")
                }

                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Label(
                            tokenStore.hasToken ? "Stored" : "Not stored",
                            systemImage: tokenStore.hasToken ? "checkmark.circle.fill" : "circle.dashed"
                        )
                        .foregroundStyle(tokenStore.hasToken ? Color.green : Color.secondary)
                    }

                    if tokenStore.hasToken {
                        Button("Remove token", role: .destructive, action: remove)
                    }
                }
            }
            .navigationTitle("API Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Keychain error",
                isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                ),
                presenting: alertMessage
            ) { _ in
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    private func save() {
        let token = trimmedInput
        guard !token.isEmpty else { return }

        do {
            try tokenStore.save(token)
            // Drop the secret from view state as soon as it is stored; nothing on
            // this screen ever needs it again.
            tokenInput = ""
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try tokenStore.clear()
            tokenInput = ""
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

#Preview {
    APISettingsView(tokenStore: TokenStore())
}
