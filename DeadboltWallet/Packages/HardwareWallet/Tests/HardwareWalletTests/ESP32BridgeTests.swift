import XCTest
import Foundation
@testable import HardwareWallet
import DeadboltCore

final class ESP32BridgeTests: XCTestCase {

    // MARK: - Test fixtures

    /// A known 32-byte public key as hex (all 0x01 bytes for simplicity).
    static let testPubkeyHex = String(repeating: "01", count: 32)

    /// The corresponding base58 address for 32 bytes of 0x01.
    /// (We only verify the hex roundtrip, not the base58 value specifically.)
    static let testAddress = "4vJ9JU1bJJE96FWSJKvHsmmFADCg4gpZQff4P3bkLKi"

    /// A known 64-byte signature as hex (all 0xab bytes for simplicity).
    static let testSignatureHex = String(repeating: "ab", count: 64)

    /// A second pubkey (all 0x02 bytes) for generate tests.
    static let testPubkeyHex2 = String(repeating: "02", count: 32)
    static let testAddress2 = "8qbHbw2BbbTHBW1sbeqakYXVKRQM8Ne7pLK7m6CVfeR"

    // MARK: - Helpers

    func makeBridge() -> (ESP32SerialBridge, MockSerialPort) {
        let mockPort = MockSerialPort()
        mockPort._isOpen = true
        let bridge = ESP32SerialBridge(port: mockPort)
        return (bridge, mockPort)
    }

    // MARK: - Ping Tests

    func testPingPong() async throws {
        let (bridge, mockPort) = makeBridge()
        mockPort.queuePongResponse()

        let result = try await bridge.ping()
        XCTAssertEqual(result, "pong")

        // Verify the command that was sent
        let sent = mockPort.lastSentCommandString()
        XCTAssertNotNil(sent)
        // Parse the sent JSON to verify it contains "cmd":"ping"
        if let sentData = sent?.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: sentData) as? [String: Any] {
            XCTAssertEqual(json["cmd"] as? String, "ping")
        } else {
            XCTFail("Failed to parse sent command as JSON")
        }
    }

    func testPingInvalidResponse() async {
        let (bridge, mockPort) = makeBridge()
        mockPort.queueResponse(#"{"status":"error","msg":"unknown command"}"#)

        do {
            _ = try await bridge.ping()
            XCTFail("Expected error")
        } catch let error as HardwareWalletError {
            if case .invalidResponse = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Get Pubkey Tests

    func testGetPubkeyReturnsValidKey() async throws {
        let (bridge, mockPort) = makeBridge()
        mockPort.queuePubkeyResponse(hex: Self.testPubkeyHex, address: Self.testAddress)

        let key = try await bridge.getPublicKey()
        XCTAssertEqual(key.data.count, 32)
        XCTAssertEqual(key.data, Data(repeating: 0x01, count: 32))
    }

    func testGetPubkeyCachesResult() async throws {
        let (bridge, mockPort) = makeBridge()
        mockPort.queuePubkeyResponse(hex: Self.testPubkeyHex, address: Self.testAddress)

        let key = try await bridge.getPublicKey()

        // After getPublicKey, the publicKey property should return the cached value
        let cached = bridge.publicKey
        XCTAssertEqual(key, cached)
    }

    func testGetPubkeyErrorResponse() async {
        let (bridge, mockPort) = makeBridge()
        mockPort.queueResponse(#"{"status":"error","msg":"no key stored"}"#)

        do {
            _ = try await bridge.getPublicKey()
            XCTFail("Expected error")
        } catch let error as HardwareWalletError {
            if case .invalidResponse(let msg) = error {
                XCTAssertTrue(msg.contains("no key stored"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Sign Tests

    func testSignFlowPendingThenApproved() async throws {
        let (bridge, mockPort) = makeBridge()

        // Queue the two-step response: pending, then signed
        mockPort.queueSignPendingResponse()
        mockPort.queueSignedResponse(signatureHex: Self.testSignatureHex)

        let message = Data([0x01, 0x02, 0x03, 0x04])
        let signature = try await bridge.sign(message: message)

        XCTAssertEqual(signature.count, 64)
        XCTAssertEqual(signature, Data(repeating: 0xab, count: 64))

        // Verify the command payload contains the hex-encoded message
        if let sentStr = mockPort.sentCommands.first.flatMap({ String(data: $0, encoding: .utf8) }) {
            XCTAssertTrue(sentStr.contains("01020304"), "Sign command should contain hex payload")
        }
    }

    func testSignFlowPendingThenRejected() async {
        let (bridge, mockPort) = makeBridge()

        mockPort.queueSignPendingResponse()
        mockPort.queueRejectionResponse()

        do {
            _ = try await bridge.sign(message: Data([0x01]))
            XCTFail("Expected rejection error")
        } catch let error as HardwareWalletError {
            if case .rejected = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSignFlowTimeout() async {
        let (bridge, mockPort) = makeBridge()

        // First response is pending, then timeout (no more responses queued)
        mockPort.queueSignPendingResponse()
        // Queue a timeout error for the second receiveLine call
        mockPort.queueError(HardwareWalletError.timeout)

        do {
            _ = try await bridge.sign(message: Data([0x01]))
            XCTFail("Expected timeout error")
        } catch let error as HardwareWalletError {
            if case .timeout = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSignFlowImmediateRejection() async {
        let (bridge, mockPort) = makeBridge()

        // Device immediately rejects (no pending step)
        mockPort.queueRejectionResponse()

        do {
            _ = try await bridge.sign(message: Data([0x01]))
            XCTFail("Expected rejection error")
        } catch let error as HardwareWalletError {
            if case .rejected = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Generate Keypair Tests

    func testGenerateKeypairReturnsNewKey() async throws {
        let (bridge, mockPort) = makeBridge()
        mockPort.queueGenerateResponse(hex: Self.testPubkeyHex2, address: Self.testAddress2)

        let key = try await bridge.generateKeypair()
        XCTAssertEqual(key.data.count, 32)
        XCTAssertEqual(key.data, Data(repeating: 0x02, count: 32))
    }

    func testGenerateKeypairUpdatesCachedKey() async throws {
        let (bridge, mockPort) = makeBridge()

        // First get a pubkey
        mockPort.queuePubkeyResponse(hex: Self.testPubkeyHex, address: Self.testAddress)
        _ = try await bridge.getPublicKey()
        let firstKey = bridge.publicKey
        XCTAssertEqual(firstKey.data, Data(repeating: 0x01, count: 32))

        // Then generate a new one
        mockPort.queueGenerateResponse(hex: Self.testPubkeyHex2, address: Self.testAddress2)
        _ = try await bridge.generateKeypair()
        let newKey = bridge.publicKey
        XCTAssertEqual(newKey.data, Data(repeating: 0x02, count: 32))
    }

    // MARK: - TransactionSigner Conformance

    func testTransactionSignerConformance() async throws {
        let (bridge, mockPort) = makeBridge()

        // Get pubkey first to populate the cached key
        mockPort.queuePubkeyResponse(hex: Self.testPubkeyHex, address: Self.testAddress)
        _ = try await bridge.getPublicKey()

        // Use as TransactionSigner
        let signer: any TransactionSigner = bridge
        XCTAssertEqual(signer.publicKey.data, Data(repeating: 0x01, count: 32))

        // Sign via the protocol
        mockPort.queueSignPendingResponse()
        mockPort.queueSignedResponse(signatureHex: Self.testSignatureHex)

        let signature = try await signer.sign(message: Data([0xDE, 0xAD]))
        XCTAssertEqual(signature.count, 64)
    }

    // MARK: - Connect/Disconnect Tests

    func testConnectPerformsPingAndGetsPubkey() async throws {
        let (bridge, mockPort) = makeBridge()
        mockPort._isOpen = false  // Start closed

        // connect() should: open, ping, getPublicKey
        mockPort.queuePongResponse()
        mockPort.queuePubkeyResponse(hex: Self.testPubkeyHex, address: Self.testAddress)

        try await bridge.connect()

        XCTAssertTrue(mockPort.isOpen)
        let key = bridge.publicKey
        XCTAssertEqual(key.data, Data(repeating: 0x01, count: 32))
    }

    func testDisconnectClearsCache() async throws {
        let (bridge, mockPort) = makeBridge()

        // Get a pubkey
        mockPort.queuePubkeyResponse(hex: Self.testPubkeyHex, address: Self.testAddress)
        _ = try await bridge.getPublicKey()

        // Disconnect
        await bridge.disconnect()

        // Key should be reset to zero
        let key = bridge.publicKey
        XCTAssertEqual(key.data, Data(repeating: 0, count: 32))
    }

    // MARK: - Error Handling Tests

    func testConnectionFailedOnOpenError() async {
        let mockPort = MockSerialPort()
        mockPort.openError = HardwareWalletError.connectionFailed("USB disconnected")
        let bridge = ESP32SerialBridge(port: mockPort)

        do {
            try await bridge.connect()
            XCTFail("Expected connection error")
        } catch let error as HardwareWalletError {
            if case .connectionFailed(let msg) = error {
                XCTAssertEqual(msg, "USB disconnected")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testInvalidJsonResponse() async {
        let (bridge, mockPort) = makeBridge()
        mockPort.queueResponse("this is not json")

        do {
            _ = try await bridge.ping()
            XCTFail("Expected invalid response error")
        } catch let error as HardwareWalletError {
            if case .invalidResponse(let msg) = error {
                XCTAssertTrue(msg.contains("Failed to decode"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - HardwareWalletError Tests

    func testErrorDescriptions() {
        let errors: [HardwareWalletError] = [
            .deviceNotFound,
            .connectionFailed("test"),
            .timeout,
            .rejected,
            .invalidResponse("bad data"),
            .serialPortError("ioctl failed"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
