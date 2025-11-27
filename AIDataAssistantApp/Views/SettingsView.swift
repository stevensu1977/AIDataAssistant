import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Settings form
            Form {
                Section("AWS Bedrock Configuration") {
                    TextField("AWS Region", text: $appState.awsRegion)
                        .textFieldStyle(.roundedBorder)

                    TextField("Access Key ID", text: $appState.awsAccessKeyId)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Secret Access Key", text: $appState.awsSecretAccessKey)
                        .textFieldStyle(.roundedBorder)

                    Picker("Model", selection: $appState.bedrockModel) {
                        Text("Claude 4.5 Sonnet").tag("us.anthropic.claude-sonnet-4-5-20250929-v1:0")
                        Text("Claude 4.5 Haiku").tag("us.anthropic.claude-haiku-4-5-20251001-v1:0")
                    }

                    Text("Your AWS credentials are stored locally and never shared")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    HStack {
                        Spacer()

                        Button("Save") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.awsAccessKeyId.isEmpty ||
                                 appState.awsSecretAccessKey.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 500, height: 350)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}

