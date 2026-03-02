import Foundation
import SwiftUI
import LocalAuthentication
import DeadboltCore
import CommonCrypto

// MARK: - Auth Mode

enum AuthMode: String, CaseIterable {
    case system = "system"
    case appPassword = "appPassword"
    case biometricOnly = "biometricOnly"

    var displayName: String {
        switch self {
        case .system: return "System (Touch ID + Password)"
        case .appPassword: return "App Password"
        case .biometricOnly: return "Biometrics Only"
        }
    }
}

// MARK: - Auth Service

@MainActor
final class AuthService: ObservableObject {
    @Published var authMode: AuthMode = .system
    @Published var allowBiometricBypass: Bool = true

    /// Set by PasswordEntryView when user submits a password
    @Published var pendingPasswordResult: Bool?

    /// Controls presentation of the password entry sheet
    @Published var showPasswordEntry: Bool = false

    /// The reason string to display in the password entry prompt
    @Published var passwordEntryReason: String = ""

    /// Continuation for bridging async authenticate() with the password sheet
    private var passwordContinuation: CheckedContinuation<Bool, Never>?

    // MARK: - Initialization

    func loadFromConfig() async {
        let config = AppConfig()
        try? await config.load()
        let mode = await config.authMode
        let bypass = await config.allowBiometricBypass
        self.authMode = AuthMode(rawValue: mode) ?? .system
        self.allowBiometricBypass = bypass
    }

    private func saveToConfig() async {
        let config = AppConfig()
        try? await config.load()
        await config.update(authMode: authMode.rawValue)
        await config.update(allowBiometricBypass: allowBiometricBypass)
        try? await config.save()
    }

    // MARK: - Mode Switching

    func setMode(_ mode: AuthMode) async {
        authMode = mode
        await saveToConfig()
    }

    func setBiometricBypass(_ allowed: Bool) async {
        allowBiometricBypass = allowed
        await saveToConfig()
    }

    // MARK: - Main Authentication Entry Point

    /// Authenticate the user based on the current auth mode.
    /// Returns true if authenticated, false if cancelled/denied.
    func authenticate(reason: String) async -> Bool {
        switch authMode {
        case .system:
            return await authenticateSystem(reason: reason)
        case .appPassword:
            return await authenticateAppPassword(reason: reason)
        case .biometricOnly:
            return await authenticateBiometricOnly(reason: reason)
        }
    }

    // MARK: - System Auth (Touch ID + System Password)

    private func authenticateSystem(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            #if DEBUG
            return true // Allow through in debug builds (VMs, CI)
            #else
            return false
            #endif
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return true
        } catch {
            return false
        }
    }

    // MARK: - App Password Auth

    private func authenticateAppPassword(reason: String) async -> Bool {
        // Try biometric bypass first if enabled
        if allowBiometricBypass {
            let biometricResult = await attemptBiometric(reason: reason)
            if biometricResult {
                return true
            }
            // Biometric failed or cancelled — fall through to password
        }

        // Present password entry sheet and wait for result
        return await withCheckedContinuation { continuation in
            self.passwordContinuation = continuation
            self.passwordEntryReason = reason
            self.showPasswordEntry = true
        }
    }

    /// Called by PasswordEntryView when user submits correct password
    func completePasswordEntry(success: Bool) {
        showPasswordEntry = false
        passwordContinuation?.resume(returning: success)
        passwordContinuation = nil
    }

    // MARK: - Biometric Only Auth

    private func authenticateBiometricOnly(reason: String) async -> Bool {
        return await attemptBiometric(reason: reason)
    }

    // MARK: - Biometric Helper

    private func attemptBiometric(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "" // Hide "Enter Password" fallback
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            #if DEBUG
            return true // Allow through in debug builds (VMs, CI)
            #else
            return false
            #endif
        }
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Password Management (PBKDF2-HMAC-SHA256)

    /// Set the app password. Derives hash with PBKDF2 and stores salt+hash in Keychain.
    func setAppPassword(_ password: String) throws {
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else {
            throw SolanaError.authenticationFailed("Failed to generate random salt")
        }

        let hash = try deriveKey(password: password, salt: salt)
        let combined = salt + hash // 32 bytes salt + 32 bytes hash = 64 bytes
        try KeychainManager.storePasswordHash(combined)
    }

    /// Remove the app password from Keychain.
    func removeAppPassword() throws {
        try KeychainManager.deletePasswordHash()
    }

    /// Validate a password against the stored hash.
    func validateAppPassword(_ password: String) -> Bool {
        guard let stored = KeychainManager.retrievePasswordHash(), stored.count == 64 else {
            return false
        }

        let salt = stored.prefix(32)
        let storedHash = stored.suffix(32)

        guard let derivedHash = try? deriveKey(password: password, salt: Data(salt)) else {
            return false
        }

        // Constant-time comparison
        return derivedHash.withUnsafeBytes { derivedPtr in
            storedHash.withUnsafeBytes { storedPtr in
                guard let d = derivedPtr.baseAddress, let s = storedPtr.baseAddress else { return false }
                var result: UInt8 = 0
                for i in 0..<32 {
                    result |= d.load(fromByteOffset: i, as: UInt8.self) ^ s.load(fromByteOffset: i, as: UInt8.self)
                }
                return result == 0
            }
        }
    }

    /// Whether an app password is currently stored in Keychain.
    var hasAppPassword: Bool {
        KeychainManager.retrievePasswordHash() != nil
    }

    // MARK: - PBKDF2

    private func deriveKey(password: String, salt: Data) throws -> Data {
        let passwordData = Array(password.utf8)
        var derivedKey = Data(count: 32)

        let status = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordData, passwordData.count,
                    saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    310_000, // OWASP 2023 recommendation
                    derivedBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), 32
                )
            }
        }

        guard status == kCCSuccess else {
            throw SolanaError.authenticationFailed("Password key derivation failed")
        }

        return derivedKey
    }
}
