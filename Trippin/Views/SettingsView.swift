import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = KeychainStore.hasAPIKey
    @State private var connection: Bool?
    @State private var checking = false

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

                Section {
                    Button {
                        Task {
                            checking = true
                            connection = await ClaudeClient.isReachable(forceCheck: true)
                            checking = false
                        }
                    } label: {
                        HStack {
                            Text("Check connection to Claude")
                            Spacer()
                            if checking { ProgressView() }
                            else if let connection {
                                Label(connection ? "Reachable" : "Not reachable",
                                      systemImage: connection ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(connection ? .green : .orange)
                            }
                        }
                    }
                    .disabled(checking)
                } footer: {
                    if connection == false {
                        Text("Claude can't be reached from this network. Reading emails falls back to the on-device reader; recommendations need Claude. Maps, Amap, 大众点评 and your saved trip work as usual.")
                    }
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
