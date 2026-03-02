import SwiftUI

struct AuthSettingsView: View {
    @EnvironmentObject var authService: AuthService

    @State private var selectedMode: AuthMode = .system
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var statusMessage: String?
    @State private var isError: Bool = false
    @State private var showChangePassword: Bool = false

    var body: some View {
        Form {
            Section("Authentication Mode") {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(AuthMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedMode) { _, newMode in
                    handleModeChange(newMode)
                }
            }

            if selectedMode == .appPassword {
                Section("App Password") {
                    if authService.hasAppPassword {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Password is set")
                                .foregroundStyle(.secondary)
                        }

                        Button("Change Password") {
                            showChangePassword.toggle()
                            newPassword = ""
                            confirmPassword = ""
                            statusMessage = nil
                        }
                    }

                    if !authService.hasAppPassword || showChangePassword {
                        SecureField("New Password", text: $newPassword)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)

                        Button(authService.hasAppPassword ? "Update Password" : "Set Password") {
                            setPassword()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newPassword.isEmpty || newPassword != confirmPassword)
                    }

                    Toggle("Allow Touch ID bypass", isOn: Binding(
                        get: { authService.allowBiometricBypass },
                        set: { newValue in
                            Task { await authService.setBiometricBypass(newValue) }
                        }
                    ))

                    Text("When enabled, Touch ID can be used instead of typing your password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if selectedMode == .biometricOnly {
                Section("Biometrics Only") {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("If Touch ID is unavailable, you won't be able to sign transactions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let message = statusMessage {
                Section {
                    HStack {
                        Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(isError ? .red : .green)
                        Text(message)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Authentication")
        .onAppear {
            selectedMode = authService.authMode
        }
    }

    private func handleModeChange(_ newMode: AuthMode) {
        statusMessage = nil

        switch newMode {
        case .system:
            // Revert — clean up app password if switching away
            Task {
                await authService.setMode(.system)
            }

        case .appPassword:
            if !authService.hasAppPassword {
                // Don't commit mode yet — wait until password is set
                newPassword = ""
                confirmPassword = ""
            } else {
                Task { await authService.setMode(.appPassword) }
            }

        case .biometricOnly:
            Task { await authService.setMode(.biometricOnly) }
        }
    }

    private func setPassword() {
        guard newPassword == confirmPassword else {
            statusMessage = "Passwords don't match"
            isError = true
            return
        }
        guard newPassword.count >= 4 else {
            statusMessage = "Password must be at least 4 characters"
            isError = true
            return
        }

        do {
            try authService.setAppPassword(newPassword)
            Task { await authService.setMode(.appPassword) }
            statusMessage = "Password set successfully"
            isError = false
            newPassword = ""
            confirmPassword = ""
            showChangePassword = false
        } catch {
            statusMessage = "Failed to set password: \(error.localizedDescription)"
            isError = true
        }
    }
}
