import XCTest
@testable import DeadboltCore

final class SystemProgramTests: XCTestCase {

    func testTransferInstructionData() throws {
        let from = try SolanaPublicKey(data: Data(repeating: 1, count: 32))
        let to = try SolanaPublicKey(data: Data(repeating: 2, count: 32))

        let ix = SystemProgram.transfer(from: from, to: to, lamports: 1_000_000_000)

        // Instruction data: u32(2) + u64(1_000_000_000)
        XCTAssertEqual(ix.data.count, 12)

        // First 4 bytes: transfer instruction index = 2 (LE)
        XCTAssertEqual(ix.data[0], 2)
        XCTAssertEqual(ix.data[1], 0)
        XCTAssertEqual(ix.data[2], 0)
        XCTAssertEqual(ix.data[3], 0)

        // Next 8 bytes: 1_000_000_000 = 0x3B9ACA00 in LE
        XCTAssertEqual(ix.data[4], 0x00)
        XCTAssertEqual(ix.data[5], 0xCA)
        XCTAssertEqual(ix.data[6], 0x9A)
        XCTAssertEqual(ix.data[7], 0x3B)
        XCTAssertEqual(ix.data[8], 0x00)
        XCTAssertEqual(ix.data[9], 0x00)
        XCTAssertEqual(ix.data[10], 0x00)
        XCTAssertEqual(ix.data[11], 0x00)
    }

    func testTransferAccountMetas() throws {
        let from = try SolanaPublicKey(data: Data(repeating: 1, count: 32))
        let to = try SolanaPublicKey(data: Data(repeating: 2, count: 32))

        let ix = SystemProgram.transfer(from: from, to: to, lamports: 100)

        XCTAssertEqual(ix.accounts.count, 2)
        XCTAssertEqual(ix.accounts[0].publicKey, from)
        XCTAssertTrue(ix.accounts[0].isSigner)
        XCTAssertTrue(ix.accounts[0].isWritable)
        XCTAssertEqual(ix.accounts[1].publicKey, to)
        XCTAssertFalse(ix.accounts[1].isSigner)
        XCTAssertTrue(ix.accounts[1].isWritable)
    }

    func testTransferProgramId() throws {
        let from = try SolanaPublicKey(data: Data(repeating: 1, count: 32))
        let to = try SolanaPublicKey(data: Data(repeating: 2, count: 32))
        let ix = SystemProgram.transfer(from: from, to: to, lamports: 100)

        XCTAssertEqual(ix.programId.base58, "11111111111111111111111111111111")
    }
}
