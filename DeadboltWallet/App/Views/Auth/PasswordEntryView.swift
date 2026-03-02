import SwiftUI

struct PasswordEntryView: View {
    @EnvironmentObject var authService: AuthService

    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var failedAttempts: Int = 0
    @State private var lockedUntil: Date?
    @State private var lockCountdown: Int = 0
    @State private var lockTimer: Task<Void, Never>?

    private let maxAttempts = 5
    private let lockDuration = 30

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Image(systemName: "lock.fill")
                .font(.title)
                .foregroundStyle(.blue)

            Text("Enter App Password")
                .font(.headline)

            if !authService.passwordEntryReason.isEmpty {
                Text(authService.passwordEntryReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Password field
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .disabled(isLocked)
                .onSubmit {
                    verify()
                }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Lock message
            if isLocked {
                Text("Too many attempts. Try again in \(lockCountdown)s")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    authService.completePasswordEntry(success: false)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("Verify") {
                    verify()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isLocked)
                .keyboardShortcut(.defaultAction)
            }

            // Attempt counter
            if failedAttempts > 0 && !isLocked {
                Text("\(maxAttempts - failedAttempts) attempts remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 360, height: 320)
    }

    private var isLocked: Bool {
        guard let until = lockedUntil else { return false }
        return Date() < until
    }

    private func verify() {
        guard !isLocked else { return }

        if authService.validateAppPassword(password) {
            // Reset state
            failedAttempts = 0
            errorMessage = nil
            password = ""
            authService.completePasswordEntry(success: true)
        } else {
            failedAttempts += 1
            password = ""

            if failedAttempts >= maxAttempts {
                errorMessage = nil
                let until = Date().addingTimeInterval(TimeInterval(lockDuration))
                lockedUntil = until
                lockCountdown = lockDuration
                lockTimer?.cancel()
                lockTimer = Task {
                    for i in stride(from: lockDuration - 1, through: 0, by: -1) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        lockCountdown = i
                    }
                    lockedUntil = nil
                    failedAttempts = 0
                }
            } else {
                errorMessage = "Incorrect password"
            }
        }
    }
}
