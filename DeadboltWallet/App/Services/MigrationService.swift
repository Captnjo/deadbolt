import Foundation
import DeadboltCore

/// Represents an unsecured keypair file found on disk.
struct UnsecuredKeypair: Identifiable, Sendable {
    let id: String // file path
    let address: String
    let path: String
}

/// P8-018: Data migration from CLI config files.
/// On first launch, checks for existing CLI data and imports it:
/// - Reads ~/.config/solana/cli/config.yml for RPC URL + keypair path
/// - Reads ~/.config/solana/deadbolt/addressBook.txt for contacts
/// - Imports discovered keypairs to Keychain
/// Sets a "migrated" flag in AppConfig so it only runs once.
actor MigrationService {

    private let config: AppConfig
    private let addressBook: AddressBook

    /// Key stored in UserDefaults to track whether migration has run.
    private static let migrationCompletedKey = "deadbolt_cli_migration_completed"

    init(config: AppConfig = AppConfig(), addressBook: AddressBook = AddressBook()) {
        self.config = config
        self.addressBook = addressBook
    }

    /// Returns true if migration has already been completed.
    var hasMigrated: Bool {
        UserDefaults.standard.bool(forKey: Self.migrationCompletedKey)
    }

    /// One-time cleanup key for removing auto-imported hot wallets.
    private static let hotWalletCleanupKey = "deadbolt_hotwallet_cleanup_completed"

    /// Run the CLI data migration. Idempotent — skips if already completed.
    func migrateIfNeeded() async {
        // One-time cleanup: remove any previously auto-imported keychain hot wallets
        if !UserDefaults.standard.bool(forKey: Self.hotWalletCleanupKey) {
            if let addresses = try? KeychainManager.listStoredAddresses() {
                for addr in addresses {
                    try? KeychainManager.deleteSeed(address: addr)
                }
            }
            UserDefaults.standard.set(true, forKey: Self.hotWalletCleanupKey)
        }

        guard !hasMigrated else { return }

        // Migrate Solana CLI config (RPC URL only, no keypair import)
        await migrateSolanaConfig()

        // Migrate address book
        await migrateAddressBook()

        // Mark migration as complete
        UserDefaults.standard.set(true, forKey: Self.migrationCompletedKey)
    }

    // MARK: - Solana CLI Config Migration

    /// Read ~/.config/solana/cli/config.yml and import RPC URL + keypair.
    private func migrateSolanaConfig() async {
        #if os(iOS)
        // CLI config migration is not applicable on iOS
        return
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(home)/.config/solana/cli/config.yml"

        guard FileManager.default.fileExists(atPath: configPath) else {
            return
        }

        do {
            let contents = try String(contentsOfFile: configPath, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Parse RPC URL
                if trimmed.hasPrefix("json_rpc_url:") {
                    let value = trimmed
                        .replacingOccurrences(of: "json_rpc_url:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                    if !value.isEmpty, URL(string: value) != nil {
                        await config.update(rpcURL: value)
                    }
                }

                // Parse keypair path
                if trimmed.hasPrefix("keypair_path:") {
                    let value = trimmed
                        .replacingOccurrences(of: "keypair_path:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                    // Expand ~ if present
                    let expandedPath: String
                    if value.hasPrefix("~") {
                        expandedPath = value.replacingOccurrences(of: "~", with: home)
                    } else {
                        expandedPath = value
                    }

                    await importKeypairFile(at: expandedPath)
                }
            }

            try await config.save()
        } catch {
            // Migration failure is non-critical; log and continue
        }
        #endif
    }

    /// Import a keypair file from disk into Keychain.
    /// Disabled by default — hardware wallet is the primary signer.
    /// Users can manually import keypairs through Settings > Create Wallet.
    private func importKeypairFile(at path: String) async {
        // No-op: don't auto-import CLI keypairs into Keychain.
        // The app is hardware-wallet-first.
    }

    // MARK: - Unsecured Keypair Detection

    /// Scan standard directories for unencrypted keypair JSON files that aren't in Keychain.
    func scanForUnsecuredKeypairs() -> [UnsecuredKeypair] {
        #if os(iOS)
        return []
        #else
        let keypairs = KeypairReader.discoverKeypairs()
        let keychainAddresses = (try? KeychainManager.listStoredAddresses()) ?? []

        return keypairs.compactMap { kp in
            // Skip if already in Keychain
            guard !keychainAddresses.contains(kp.publicKey.base58) else { return nil }
            guard let path = kp.sourcePath else { return nil }
            return UnsecuredKeypair(id: path, address: kp.publicKey.base58, path: path)
        }
        #endif
    }

    /// Import a keypair file into Keychain and optionally secure-delete the original file.
    /// Verifies the Keychain write succeeded (read-back) before deleting the original.
    func importAndSecureDelete(path: String, deleteOriginal: Bool) throws {
        let keypair = try KeypairReader.read(from: path)
        try KeychainManager.storeSeed(keypair.seed, address: keypair.publicKey.base58)

        // Verify the Keychain write by reading back the seed
        let readBack = try KeychainManager.retrieveSeed(address: keypair.publicKey.base58)
        guard readBack == keypair.seed else {
            throw SolanaError.decodingError("Keychain read-back verification failed for \(keypair.publicKey.base58.prefix(8))...")
        }

        if deleteOriginal {
            // Overwrite file contents with random bytes before deleting
            let fileURL = URL(fileURLWithPath: path)
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int, fileSize > 0 {
                var randomBytes = [UInt8](repeating: 0, count: fileSize)
                _ = SecRandomCopyBytes(kSecRandomDefault, fileSize, &randomBytes)
                try Data(randomBytes).write(to: fileURL)
            }
            try FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Address Book Migration

    /// Read ~/.config/solana/deadbolt/addressBook.txt and import contacts.
    /// Expected format: one entry per line, "tag address" separated by whitespace.
    private func migrateAddressBook() async {
        #if os(iOS)
        // CLI address book migration is not applicable on iOS
        return
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let addressBookPath = "\(home)/.config/solana/deadbolt/addressBook.txt"

        guard FileManager.default.fileExists(atPath: addressBookPath) else {
            return
        }

        do {
            try await addressBook.load()
            let contents = try String(contentsOfFile: addressBookPath, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

                // Parse "tag address" or "address tag" format
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard parts.count >= 2 else { continue }

                // Determine which part is the address (44-char base58)
                let (tag, address): (String, String)
                if parts[0].count >= 32 && parts[0].count <= 44 {
                    // First part looks like an address
                    address = parts[0]
                    tag = parts[1...].joined(separator: " ")
                } else {
                    // First part is the tag
                    tag = parts[0]
                    address = parts[1]
                }

                // Try to add the entry (will validate the address)
                do {
                    try await addressBook.add(address: address, tag: tag)
                } catch {
                    // Skip invalid or duplicate entries
                }
            }

            try await addressBook.save()
        } catch {
            // Address book migration failure is non-critical
        }
        #endif
    }
}
