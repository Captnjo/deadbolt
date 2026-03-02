import XCTest
@testable import DeadboltCore

final class Base58Tests: XCTestCase {

    // MARK: - Round-trip

    func testRoundTripEmpty() throws {
        let data = Data()
        let encoded = Base58.encode(data)
        let decoded = try Base58.decode(encoded)
        XCTAssertEqual(data, decoded)
    }

    func testRoundTripSingleByte() throws {
        for byte: UInt8 in [0, 1, 57, 58, 127, 255] {
            let data = Data([byte])
            let encoded = Base58.encode(data)
            let decoded = try Base58.decode(encoded)
            XCTAssertEqual(data, decoded, "Failed for byte \(byte)")
        }
    }

    func testRoundTripRandomData() throws {
        for _ in 0..<100 {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let data = Data(bytes)
            let encoded = Base58.encode(data)
            let decoded = try Base58.decode(encoded)
            XCTAssertEqual(data, decoded)
        }
    }

    // MARK: - Known Solana addresses

    func testKnownSolanaSystemProgram() throws {
        // System Program: 11111111111111111111111111111111 (32 zero bytes)
        let data = Data(repeating: 0, count: 32)
        let encoded = Base58.encode(data)
        XCTAssertEqual(encoded, "11111111111111111111111111111111")

        let decoded = try Base58.decode("11111111111111111111111111111111")
        XCTAssertEqual(decoded, data)
    }

    func testKnownSolanaTokenProgram() throws {
        // Token Program: TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA
        let decoded = try Base58.decode("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        XCTAssertEqual(decoded.count, 32)
        let reencoded = Base58.encode(decoded)
        XCTAssertEqual(reencoded, "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
    }

    // MARK: - Leading zeros

    func testLeadingZeros() throws {
        let data = Data([0, 0, 0, 1, 2, 3])
        let encoded = Base58.encode(data)
        XCTAssertTrue(encoded.hasPrefix("111"), "Leading zeros should map to '1' characters")
        let decoded = try Base58.decode(encoded)
        XCTAssertEqual(data, decoded)
    }

    // MARK: - Invalid characters

    func testInvalidCharacterThrows() {
        XCTAssertThrowsError(try Base58.decode("0OIl")) { error in
            // '0', 'O', 'I', 'l' are not in Base58 alphabet
            guard case SolanaError.invalidBase58Character = error else {
                XCTFail("Expected invalidBase58Character, got \(error)")
                return
            }
        }
    }

    func testInvalidCharacterSpace() {
        XCTAssertThrowsError(try Base58.decode("abc def"))
    }
}
