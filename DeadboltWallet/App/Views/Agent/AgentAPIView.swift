import SwiftUI
import DeadboltCore

/// Shows Agent API server status, API keys, and pending requests.
struct AgentAPIView: View {
    @EnvironmentObject var agentService: AgentService
    @EnvironmentObject var authService: AuthService

    @State private var newKeyLabel = ""
    @State private var isAddingKey = false
    @State private var keyToRemove: APIKey?
    @State private var showRemoveConfirmation = false
    @State private var copiedCurl = false

    var body: some View {
        Form {
            Section("Server Status") {
                HStack {
                    Circle()
                        .fill(agentService.isServerRunning ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(agentService.isServerRunning ? "Running" : "Stopped")
                    Spacer()
                    Text("Port \(agentService.serverPort)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let error = agentService.serverError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                HStack {
                    Text("Pending Requests")
                    Spacer()
                    Text("\(agentService.pendingRequestCount)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("API Keys") {
                if agentService.apiTokens.isEmpty {
                    Text("No API keys")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(agentService.apiTokens) { key in
                        APIKeyRow(key: key) {
                            keyToRemove = key
                            showRemoveConfirmation = true
                        }
                    }
                }

                if isAddingKey {
                    HStack {
                        TextField("Key label (e.g. Trading Bot)", text: $newKeyLabel)
                            .textFieldStyle(.roundedBorder)
                        Button("Create") {
                            let label = newKeyLabel.trimmingCharacters(in: .whitespaces)
                            guard !label.isEmpty else { return }
                            Task {
                                await agentService.addToken(label: label)
                                newKeyLabel = ""
                                isAddingKey = false
                            }
                        }
                        .disabled(newKeyLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") {
                            newKeyLabel = ""
                            isAddingKey = false
                        }
                    }
                } else {
                    Button {
                        isAddingKey = true
                    } label: {
                        Label("Add Key", systemImage: "plus")
                    }
                }
            }
            .alert("Remove API Key?", isPresented: $showRemoveConfirmation) {
                Button("Remove", role: .destructive) {
                    guard let key = keyToRemove else { return }
                    Task {
                        let authed = await authService.authenticate(reason: "Remove API key \"\(key.label)\"")
                        if authed {
                            await agentService.removeToken(id: key.id)
                        }
                        keyToRemove = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    keyToRemove = nil
                }
            } message: {
                if let key = keyToRemove {
                    Text("This will permanently revoke the key \"\(key.label)\". Any agents using it will lose access.")
                }
            }

            Section("Quick Test") {
                if let firstToken = agentService.apiTokens.first {
                    let curlCommand = """
                    curl -H "Authorization: Bearer \(firstToken.token)" \
                         http://localhost:\(agentService.serverPort)/api/v1/health
                    """
                    let maskedCommand = """
                    curl -H "Authorization: Bearer <your-token>" \
                         http://localhost:\(agentService.serverPort)/api/v1/health
                    """
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(maskedCommand)
                                .font(.system(.caption2, design: .monospaced))
                                .padding(8)
                            Spacer()
                            Button {
                                #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(curlCommand, forType: .string)
                                #endif
                                copiedCurl = true
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    copiedCurl = false
                                }
                            } label: {
                                Image(systemName: copiedCurl ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(copiedCurl ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Copy curl command (includes real token)")
                            .padding(8)
                        }
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text("Checks that the Agent API server is reachable and your token is valid. Expects a 200 OK response.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Agent API")
    }
}

// MARK: - API Key Row

private struct APIKeyRow: View {
    let key: APIKey
    let onRemove: () -> Void

    @State private var showToken = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(key.label)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            if showToken {
                Text(key.token)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
            } else {
                Text("db_" + String(repeating: "•", count: 16))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                showToken.toggle()
            } label: {
                Image(systemName: showToken ? "eye.slash" : "eye")
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(showToken ? "Hide token" : "Show token")

            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key.token, forType: .string)
                #endif
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 20)
                    .foregroundStyle(copied ? .green : .primary)
            }
            .buttonStyle(.plain)
            .help("Copy token")

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .frame(width: 20)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove key")
        }
    }
}
