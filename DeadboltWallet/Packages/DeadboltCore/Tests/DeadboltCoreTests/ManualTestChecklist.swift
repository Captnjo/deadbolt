import XCTest
@testable import DeadboltCore

/// P9-007: Manual testing checklist.
/// Each test represents a manual verification scenario that should be tested on a real device/simulator.
/// All tests are skipped with descriptions of what to verify.
final class ManualTestChecklist: XCTestCase {

    // MARK: - Send SOL

    func testManual_sendSOL_softwareWallet() throws {
        throw XCTSkip("""
            Manual test: Send SOL with software wallet.
            Steps:
            1. Load a funded software wallet
            2. Navigate to Send flow
            3. Enter a valid recipient address
            4. Enter an amount (e.g., 0.001 SOL)
            5. Verify the transaction preview shows correct amount, recipient, and fee estimate
            6. Confirm the transaction
            7. Verify the signature is displayed
            8. Verify the recipient balance increased
            9. Verify the sender balance decreased by amount + fee
            """)
    }

    func testManual_sendSOL_hardwareWallet() throws {
        throw XCTSkip("""
            Manual test: Send SOL with hardware wallet.
            Steps:
            1. Connect the hardware wallet via serial port
            2. Load a funded hardware wallet
            3. Navigate to Send flow
            4. Enter a valid recipient address and amount
            5. Verify the transaction preview is shown
            6. Confirm -- the transaction should be sent to the hardware device for signing
            7. Verify the hardware device displays the transaction details
            8. Approve on the hardware device
            9. Verify the signed transaction is submitted and confirmed
            """)
    }

    // MARK: - Send Token

    func testManual_sendToken_withATACreation() throws {
        throw XCTSkip("""
            Manual test: Send SPL token to a recipient that does NOT have an ATA.
            Steps:
            1. Load a wallet with some USDC (or other SPL token)
            2. Navigate to Send Token flow
            3. Select the token
            4. Enter a recipient address that does NOT have an ATA for that token
            5. Verify the transaction preview includes ATA creation + token transfer
            6. Verify ATA creation cost is reflected in the fee estimate
            7. Confirm and verify the transaction succeeds
            8. Verify the recipient now has the ATA and the token balance
            """)
    }

    // MARK: - Send NFT

    func testManual_sendNFT() throws {
        throw XCTSkip("""
            Manual test: Send an NFT.
            Steps:
            1. Load a wallet that holds at least one NFT
            2. Navigate to Send NFT flow
            3. Select an NFT from the list (verify images load correctly)
            4. Enter a recipient address
            5. Verify the transaction preview shows the NFT name and recipient
            6. Confirm and verify the NFT transfer succeeds
            7. Verify the NFT no longer appears in the sender's dashboard
            """)
    }

    // MARK: - Jupiter Swap

    func testManual_jupiterSwap() throws {
        throw XCTSkip("""
            Manual test: Jupiter swap (SOL -> USDC or similar).
            Steps:
            1. Load a funded wallet
            2. Navigate to Swap flow
            3. Select input token (SOL) and output token (USDC)
            4. Enter an amount
            5. Verify a quote is fetched and displayed (rate, price impact, route)
            6. Confirm the swap
            7. Verify the transaction is submitted via Jito bundle
            8. Verify the output token balance increased
            9. Verify the input token balance decreased
            """)
    }

    // MARK: - Sanctum Staking

    func testManual_sanctumStake() throws {
        throw XCTSkip("""
            Manual test: Stake SOL via Sanctum (SOL -> jitoSOL/mSOL/bSOL).
            Steps:
            1. Load a funded wallet
            2. Navigate to Stake flow
            3. Select an LST (e.g., jitoSOL)
            4. Enter amount to stake
            5. Verify quote shows expected LST amount and fee
            6. Confirm the stake
            7. Verify the LST balance appears on the dashboard
            8. Verify the SOL balance decreased
            """)
    }

    // MARK: - Wallet Management

    func testManual_walletCreate_random() throws {
        throw XCTSkip("""
            Manual test: Create a random wallet.
            Steps:
            1. Navigate to Create Wallet
            2. Select "Generate Random"
            3. Verify a 12-word seed phrase is displayed
            4. Verify a "Write down your seed phrase!" warning is shown
            5. Verify the public address is displayed
            6. Dismiss and verify the wallet appears in the wallet list
            7. Verify the wallet is stored in the Keychain
            """)
    }

    func testManual_walletCreate_vanity() throws {
        throw XCTSkip("""
            Manual test: Create a vanity wallet.
            Steps:
            1. Navigate to Create Wallet
            2. Select "Vanity Address"
            3. Enter a short prefix (e.g., "ab")
            4. Click Generate and verify progress counter increments
            5. Wait for a match (should be quick for 2-char prefix)
            6. Verify the resulting address starts with the prefix (case-insensitive)
            7. Dismiss and verify the wallet appears in the wallet list
            """)
    }

    func testManual_walletImport_seedPhrase() throws {
        throw XCTSkip("""
            Manual test: Import wallet from seed phrase.
            Steps:
            1. Navigate to Create Wallet
            2. Select "Import Seed Phrase"
            3. Enter a known 12-word seed phrase
            4. Click Import
            5. Verify the derived public key matches the expected address
            6. Verify the wallet is stored in the Keychain
            7. Test with invalid words -- should show error
            8. Test with wrong word count -- should show error
            """)
    }

    func testManual_walletImport_keypairFile() throws {
        throw XCTSkip("""
            Manual test: Import wallet from keypair JSON file.
            Steps:
            1. Have a Solana CLI keypair JSON file ready
            2. Navigate to Wallets view
            3. Import the keypair file
            4. Verify the public key matches the expected address
            5. Verify the wallet appears in the wallet list
            6. Test with a malformed file -- should show error
            """)
    }

    // MARK: - Address Book

    func testManual_addressBook_CRUD() throws {
        throw XCTSkip("""
            Manual test: Address book create, read, update, delete.
            Steps:
            1. Navigate to Address Book
            2. Add a new entry (label + valid Solana address)
            3. Verify it appears in the list
            4. Edit the label
            5. Verify the updated label is shown
            6. Delete the entry
            7. Verify it is removed from the list
            8. Try adding an entry with an invalid address -- should show error
            9. Try adding a duplicate address -- verify behavior
            """)
    }

    // MARK: - Transaction History

    func testManual_transactionHistory_load() throws {
        throw XCTSkip("""
            Manual test: Transaction history loading and display.
            Steps:
            1. Load a wallet with transaction history
            2. Navigate to History view
            3. Verify transactions load (transfers, swaps, etc.)
            4. Verify each entry shows: type icon, description, amount, timestamp
            5. Click a transaction to see details
            6. Verify the detail view shows signature, fee, participants
            7. Test with a wallet that has no history -- verify empty state
            """)
    }

    // MARK: - Agent Intent API (Phase 2)

    func testManual_agentIntent_sendSOL() throws {
        throw XCTSkip("""
            Manual test: Agent submits a send_sol intent via API.
            Steps:
            1. Start the app (API server auto-starts on port 9876)
            2. Generate an API token in Settings > Agent API
            3. POST /api/v1/intent with send_sol body:
               curl -X POST http://127.0.0.1:9876/api/v1/intent \\
                 -H "Authorization: Bearer db_<token>" \\
                 -H "Content-Type: application/json" \\
                 -d '{"type":"send_sol","params":{"recipient":"<addr>","amount":1000000},"metadata":{"agent_id":"test","reason":"manual test"}}'
            4. Verify the signing prompt modal appears in the app
            5. Verify agent_id, reason, action description, and fee breakdown are shown
            6. Approve the transaction
            7. Poll GET /api/v1/status/<request_id> and verify status becomes "confirmed"
            8. Verify the signature is present in the response
            """)
    }

    func testManual_agentIntent_swap() throws {
        throw XCTSkip("""
            Manual test: Agent submits a swap intent via API.
            Steps:
            1. Ensure app is running with funded wallet
            2. POST /api/v1/intent with swap body (SOL -> USDC)
            3. Verify the signing prompt shows swap preview with expected amounts
            4. Verify simulation result is shown (success + compute units)
            5. Approve the swap
            6. Verify status transitions: pending_approval -> building -> signing -> submitted -> confirmed
            7. Verify output token balance changed
            """)
    }

    func testManual_agentIntent_rejection() throws {
        throw XCTSkip("""
            Manual test: Reject an agent intent.
            Steps:
            1. POST any intent via API
            2. Verify signing prompt appears
            3. Click "Reject"
            4. Poll status endpoint and verify status is "rejected"
            5. Verify no transaction was submitted
            """)
    }

    func testManual_agentIntent_hardwareApproval() throws {
        throw XCTSkip("""
            Manual test: Approve agent intent with hardware wallet.
            Steps:
            1. Connect ESP32 hardware wallet
            2. Select hardware wallet as active wallet
            3. POST intent via API
            4. Verify signing prompt shows "Press BOOT button on ESP32"
            5. Press BOOT button on ESP32
            6. Verify transaction is signed by hardware and submitted
            7. Verify confirmed status in API response
            """)
    }

    func testManual_agentIntent_batchIntent() throws {
        throw XCTSkip("""
            Manual test: Submit a batch intent.
            Steps:
            1. POST batch intent with 2-3 operations:
               {"type":"batch","intents":[{"type":"swap",...},{"type":"stake",...}]}
            2. Verify signing prompt shows all operations
            3. Approve the batch
            4. Verify all operations executed in order
            """)
    }

    // MARK: - Guardrails (Phase 2)

    func testManual_guardrails_maxSOLRejection() throws {
        throw XCTSkip("""
            Manual test: Guardrail rejects intent exceeding max SOL.
            Steps:
            1. Set max SOL per transaction to 1 SOL in Settings > Guardrails
            2. POST send_sol intent for 2 SOL via API
            3. Verify the intent is auto-rejected (no signing prompt)
            4. Verify status response shows "rejected" with guardrail reason
            """)
    }

    func testManual_guardrails_dailyLimit() throws {
        throw XCTSkip("""
            Manual test: Daily transaction limit.
            Steps:
            1. Set daily transaction limit to 3 in Settings > Guardrails
            2. Submit and approve 3 intents
            3. Submit a 4th intent
            4. Verify the 4th is auto-rejected due to daily limit
            """)
    }

    func testManual_guardrails_tokenWhitelist() throws {
        throw XCTSkip("""
            Manual test: Token whitelist enforcement.
            Steps:
            1. Add only SOL and USDC to token whitelist
            2. Submit a swap intent involving a non-whitelisted token
            3. Verify auto-rejection with appropriate message
            4. Submit a swap intent for SOL -> USDC
            5. Verify it passes guardrails and reaches signing prompt
            """)
    }

    func testManual_guardrails_cooldown() throws {
        throw XCTSkip("""
            Manual test: Cooldown between transactions.
            Steps:
            1. Set cooldown to 10 seconds
            2. Submit and approve an intent
            3. Immediately submit another intent from the same agent
            4. Verify the second is rejected due to cooldown
            5. Wait 10 seconds and resubmit
            6. Verify it now passes
            """)
    }

    // MARK: - Query Endpoints (Phase 2)

    func testManual_queryEndpoints() throws {
        throw XCTSkip("""
            Manual test: All query endpoints return valid data.
            Steps:
            1. Load a funded wallet
            2. GET /api/v1/wallet — verify address, source, network
            3. GET /api/v1/balance — verify sol_lamports > 0, sol_display, sol_usd
            4. GET /api/v1/tokens — verify token list with mints, symbols, amounts
            5. GET /api/v1/price?mint=<SOL_MINT> — verify price_usd is reasonable
            6. GET /api/v1/history?limit=5 — verify recent transactions listed
            7. Run tests/test_intent_api.sh for automated coverage
            """)
    }

    // MARK: - External Bridge (Phase 2)

    func testManual_bridge_forwarding() throws {
        throw XCTSkip("""
            Manual test: External bridge forwards requests.
            Steps:
            1. Start the bridge: deadbolt-bridge --port 9877
            2. Verify GET http://localhost:9877/api/v1/health returns ok
            3. POST an intent to bridge port (9877 instead of 9876)
            4. Verify the intent appears in the app's signing prompt
            5. Approve in the app
            6. Poll status via bridge and verify confirmed
            """)
    }

    // MARK: - Settings UI (Phase 2)

    func testManual_settingsUI_agentAPI() throws {
        throw XCTSkip("""
            Manual test: Agent API settings page.
            Steps:
            1. Navigate to Settings > Agent API
            2. Verify server status indicator (green = running)
            3. Click "Generate Token" — verify db_ token is shown
            4. Click "Copy" — verify token is in clipboard
            5. Click "Reveal/Hide" — verify token masking
            6. Click "Revoke" — verify token is cleared
            7. Navigate to Settings > Guardrails
            8. Modify each guardrail value
            9. Verify changes persist after navigating away and back
            """)
    }

    // MARK: - Hardware Wallet

    func testManual_hardwareWallet_signFlow() throws {
        throw XCTSkip("""
            Manual test: Hardware wallet sign flow.
            Steps:
            1. Connect the ESP32 hardware wallet via USB serial
            2. Verify the device is detected in the app
            3. Build a transaction (e.g., SOL transfer)
            4. Send the transaction to the hardware wallet for signing
            5. Verify the device displays transaction details on its screen
            6. Approve on the hardware device
            7. Verify the signed transaction is returned to the app
            8. Verify the signature is valid
            9. Test: reject on the hardware device -- verify the app handles it
            10. Test: disconnect mid-signing -- verify error handling
            """)
    }
}
