import XCTest
import CryptoKit
@testable import DeadboltCore

final class KeypairReaderTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Valid keypair

    func testReadValidKeypair() throws {
        // Generate a known keypair: 32-byte seed → derive public key → write 64-byte JSON array
        let seed = Data(repeating: 0x42, count: 32)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let pubKey = Data(privateKey.publicKey.rawRepresentation)

        let bytes = [UInt8](seed) + [UInt8](pubKey)
        let jsonArray = bytes.map { Int($0) }
        let jsonData = try JSONEncoder().encode(jsonArray)

        let filePath = tempDir.appendingPathComponent("test.json")
        try jsonData.write(to: filePath)

        let keypair = try KeypairReader.read(from: filePath.path)
        XCTAssertEqual(keypair.seed, seed)
        XCTAssertEqual(keypair.publicKey.data, pubKey)
    }

    // MARK: - Wrong length

    func testReadWrongLengthThrows() throws {
        let jsonArray = Array(0..<32)  // Only 32 bytes, not 64
        let jsonData = try JSONEncoder().encode(jsonArray)

        let filePath = tempDir.appendingPathComponent("short.json")
        try jsonData.write(to: filePath)

        XCTAssertThrowsError(try KeypairReader.read(from: filePath.path)) { error in
            guard case SolanaError.invalidKeypairLength(32) = error else {
                XCTFail("Expected invalidKeypairLength(32), got \(error)")
                return
            }
        }
    }

    // MARK: - File not found

    func testReadMissingFileThrows() {
        XCTAssertThrowsError(try KeypairReader.read(from: "/tmp/nonexistent_keypair.json")) { error in
            guard case SolanaError.keypairFileNotFound = error else {
                XCTFail("Expected keypairFileNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Invalid JSON

    func testReadInvalidJSONThrows() throws {
        let filePath = tempDir.appendingPathComponent("bad.json")
        try "not json at all".write(to: filePath, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try KeypairReader.read(from: filePath.path)) { error in
            guard case SolanaError.keypairParseError = error else {
                XCTFail("Expected keypairParseError, got \(error)")
                return
            }
        }
    }
}
