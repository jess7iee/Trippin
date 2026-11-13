import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = KeychainStore.hasAPIKey

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if hasKey {
                        LabeledContent("Claude API key", value: "Saved")
                        Button("Remove key", role: .destructive) {
                            KeychainStore.apiKey = nil
                            hasKey = false
                        }
                    } else {
                        SecureField("sk-ant-…", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save key") {
                            KeychainStore.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                            key = ""
                            hasKey = KeychainStore.hasAPIKey
                        }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Claude")
                } footer: {
                    Text("Used for recommendations and for reading booking emails. The key stays in this device's Keychain and is only sent to api.anthropic.com. Get one at platform.claude.com.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Model", value: ClaudeClient.model)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
