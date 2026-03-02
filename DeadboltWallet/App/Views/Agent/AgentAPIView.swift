import SwiftUI

/// Shows Agent API server status, API token, and pending requests.
struct AgentAPIView: View {
    @EnvironmentObject var agentService: AgentService

    @State private var showToken = false
    @State private var copied = false

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

            Section("API Token") {
                if let token = agentService.apiToken {
                    HStack {
                        if showToken {
                            Text(token)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        } else {
                            Text("db_" + String(repeating: "*", count: 29))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Button("Copy Token") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(token, forType: .string)
                            #endif
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copied = false
                            }
                        }
                        if copied {
                            Text("Copied!")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }

                    Button("Regenerate Token") {
                        Task { await agentService.regenerateToken() }
                    }

                    Button("Revoke Token") {
                        Task { await agentService.revokeToken() }
                    }
                    .foregroundStyle(.red)
                } else {
                    Text("No API token configured")
                        .foregroundStyle(.secondary)
                    Button("Generate Token") {
                        Task { await agentService.regenerateToken() }
                    }
                }
            }

            Section("Quick Test") {
                if agentService.apiToken != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Test with curl:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let displayToken = showToken ? (agentService.apiToken ?? "") : "<your-token>"
                        Text("""
                        curl -H "Authorization: Bearer \(displayToken)" \\
                             http://localhost:\(agentService.serverPort)/api/v1/health
                        """)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Agent API")
    }
}
