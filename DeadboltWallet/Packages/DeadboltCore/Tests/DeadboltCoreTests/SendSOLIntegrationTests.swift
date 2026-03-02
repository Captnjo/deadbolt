import XCTest
@testable import DeadboltCore

/// End-to-end devnet integration test: airdrop SOL → build + sign + send transfer → confirm signature.
///
/// Requires network access to Solana devnet. Skipped unless INTEGRATION_TESTS=1 environment variable is set.
/// Run manually: INTEGRATION_TESTS=1 swift test --filter SendSOLIntegrationTests
final class SendSOLIntegrationTests: XCTestCase {

    private static let devnetURL = URL(string: "https://api.devnet.solana.com")!

    /// Random seed for each test run to avoid nonce reuse across runs
    private static func randomSeed() -> Data {
        var seed = Data(count: 32)
        seed.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        return seed
    }

    private func skipUnlessIntegration() throws {
        guard ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set INTEGRATION_TESTS=1 to run devnet integration tests")
        }
    }

    /// Request airdrop with retry logic (devnet faucet is unreliable).
    private func requestAirdropWithRetry(
        rpc: SolanaRPCClient,
        address: String,
        lamports: UInt64,
        maxRetries: Int = 3
    ) async throws -> String {
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let sig = try await rpc.requestAirdrop(address: address, lamports: lamports)
                return sig
            } catch {
                lastError = error
                if attempt < maxRetries {
                    // Backoff: 2s, 4s, 8s
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw XCTSkip("Devnet airdrop unavailable after \(maxRetries) attempts: \(lastError?.localizedDescription ?? "unknown")")
    }

    /// Wait for a signature to be confirmed, polling with backoff.
    private func waitForConfirmation(
        rpc: SolanaRPCClient,
        signature: String,
        timeout: TimeInterval = 45
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var delay: UInt64 = 2_000_000_000 // 2s

        while Date() < deadline {
            do {
                let statuses = try await rpc.getSignatureStatuses(
                    signatures: [signature],
                    searchTransactionHistory: false
                )
                if let status = statuses.first, let s = status {
                    if s.err != nil {
                        XCTFail("Transaction failed with error: \(String(describing: s.err))")
                        return
                    }
                    if let cs = s.confirmationStatus, cs == "confirmed" || cs == "finalized" {
                        return // success
                    }
                }
            } catch {
                // Transient network errors during polling are OK — keep trying
            }
            try await Task.sleep(nanoseconds: delay)
            delay = min(delay + 1_000_000_000, 5_000_000_000) // increase to 5s max
        }
        XCTFail("Timed out waiting for confirmation of \(signature)")
    }

    // MARK: - Tests

    func testDevnetSendSOL() async throws {
        try skipUnlessIntegration()

        let rpc = SolanaRPCClient(rpcURL: Self.devnetURL)

        // 1. Create a signer from a random seed
        let signer = try SoftwareSigner(seed: Self.randomSeed())
        let address = signer.publicKey.base58

        // 2. Airdrop 0.05 SOL (50_000_000 lamports)
        let airdropSig = try await requestAirdropWithRetry(
            rpc: rpc, address: address, lamports: 50_000_000
        )
        XCTAssertFalse(airdropSig.isEmpty, "Airdrop should return a signature")

        // Wait for airdrop to confirm
        try await waitForConfirmation(rpc: rpc, signature: airdropSig, timeout: 45)

        // 3. Verify balance
        let balance = try await rpc.getBalance(address: address)
        XCTAssertEqual(balance, 50_000_000, "Balance should be 0.05 SOL after airdrop")

        // 4. Create a recipient (random address)
        let recipient = try SoftwareSigner(seed: Self.randomSeed()).publicKey

        // 5. Build, sign, and send a SOL transfer (10_000 lamports = 0.00001 SOL)
        let transferAmount: UInt64 = 10_000
        let blockhashValue = try await rpc.getLatestBlockhash()

        let message = try Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhashValue.blockhash,
            instructions: [
                SystemProgram.transfer(from: signer.publicKey, to: recipient, lamports: transferAmount),
            ]
        )

        var tx = Transaction(message: message)
        try await tx.sign(with: signer)

        // Submit via standard RPC (not Jito — Jito doesn't support devnet)
        let txSignature = try await rpc.sendTransaction(
            encodedTransaction: tx.serializeBase64(),
            skipPreflight: false
        )
        XCTAssertFalse(txSignature.isEmpty, "sendTransaction should return a signature")

        // 6. Wait for transfer to confirm
        try await waitForConfirmation(rpc: rpc, signature: txSignature, timeout: 45)

        // 7. Verify recipient balance
        let recipientBalance = try await rpc.getBalance(address: recipient.base58)
        XCTAssertEqual(recipientBalance, transferAmount, "Recipient should have received \(transferAmount) lamports")

        // 8. Verify sender balance decreased (initial - transfer - baseFee)
        let senderBalance = try await rpc.getBalance(address: address)
        XCTAssertEqual(senderBalance, 50_000_000 - transferAmount - 5_000,
                       "Sender balance should be initial - transfer - base fee")
    }

    func testDevnetSendSOLWithComputeBudget() async throws {
        try skipUnlessIntegration()

        let rpc = SolanaRPCClient(rpcURL: Self.devnetURL)

        // Create signer and fund via airdrop
        let signer = try SoftwareSigner(seed: Self.randomSeed())

        // Small delay to avoid rate limiting from previous test
        try await Task.sleep(nanoseconds: 3_000_000_000)

        let airdropSig = try await requestAirdropWithRetry(
            rpc: rpc, address: signer.publicKey.base58, lamports: 50_000_000
        )
        try await waitForConfirmation(rpc: rpc, signature: airdropSig, timeout: 45)

        // Create recipient
        let recipient = try SoftwareSigner(seed: Self.randomSeed()).publicKey

        // Build transaction with compute budget instructions
        let blockhash = try await rpc.getLatestBlockhash()
        let transferAmount: UInt64 = 10_000

        let message = try Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash.blockhash,
            instructions: [
                ComputeBudgetProgram.setComputeUnitLimit(200_000),
                ComputeBudgetProgram.setComputeUnitPrice(1_000),
                SystemProgram.transfer(from: signer.publicKey, to: recipient, lamports: transferAmount),
            ]
        )

        var tx = Transaction(message: message)
        try await tx.sign(with: signer)

        let txSignature = try await rpc.sendTransaction(
            encodedTransaction: tx.serializeBase64(),
            skipPreflight: false
        )

        try await waitForConfirmation(rpc: rpc, signature: txSignature, timeout: 45)

        // Verify recipient got the transfer
        let recipientBalance = try await rpc.getBalance(address: recipient.base58)
        XCTAssertEqual(recipientBalance, transferAmount)
    }
}
