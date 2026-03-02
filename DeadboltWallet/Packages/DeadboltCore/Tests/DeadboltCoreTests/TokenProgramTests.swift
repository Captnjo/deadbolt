import XCTest
@testable import DeadboltCore

final class TokenProgramTests: XCTestCase {

    func testTransferInstructionData() throws {
        let source = try SolanaPublicKey(data: Data(repeating: 1, count: 32))
        let destination = try SolanaPublicKey(data: Data(repeating: 2, count: 32))
        let owner = try SolanaPublicKey(data: Data(repeating: 3, count: 32))

        let ix = TokenProgram.transfer(source: source, destination: destination, owner: owner, amount: 1_000_000)

        // Instruction data: u8(3) + u64(1_000_000) = 9 bytes
        XCTAssertEqual(ix.data.count, 9)

        // First byte: Transfer variant = 3
        XCTAssertEqual(ix.data[0], 3)

        // Next 8 bytes: 1_000_000 = 0x000F4240 in LE -> [0x40, 0x42, 0x0F, 0x00, ...]
        XCTAssertEqual(ix.data[1], 0x40)
        XCTAssertEqual(ix.data[2], 0x42)
        XCTAssertEqual(ix.data[3], 0x0F)
        XCTAssertEqual(ix.data[4], 0x00)
        XCTAssertEqual(ix.data[5], 0x00)
        XCTAssertEqual(ix.data[6], 0x00)
        XCTAssertEqual(ix.data[7], 0x00)
        XCTAssertEqual(ix.data[8], 0x00)
    }

    func testTransferInstructionDataMaxAmount() throws {
        let source = try SolanaPublicKey(data: Data(repeating: 1, count: 32))
        let destination = try SolanaPublicKey(data: Data(repeating: 2, count: 32))
        let owner = try SolanaPublicKey(data: Data(repeating: 3, count: 32))

        let ix = TokenProgram.transfer(source: source, destination: destination, owner: owner, amount: UInt64.max)

        XCTAssertEqual(ix.data.count, 9)
        XCTAssertEqual(ix.data[0], 3)
        // UInt64.max = 0xFFFFFFFFFFFFFFFF LE
        for i in 1..<9 {
            XCTAssertEqual(ix.data[i], 0xFF)
        }
    }

    func testTransferAccountMetas() throws {
        let source = try SolanaPublicKey(data: Data(repeating: 1, count: 32))
        let destination = try SolanaPublicKey(data: Data(repeating: 2, count: 32))
        let owner = try SolanaPublicKey(data: Data(repeating: 3, count: 32))

        let ix = TokenProgram.transfer(source: source, destination: destination, owner: owner, amount: 100)

        XCTAssertEqual(ix.accounts.count, 3)

        // source: writable, not signer
        XCTAssertEqual(ix.accounts[0].publicKey, source)
        XCTAssertFalse(ix.accounts[0].isSigner)
        XCTAssertTrue(ix.accounts[0].isWritable)

        // destination: writable, not signer
        XCTAssertEqual(ix.accounts[1].publicKey, destination)
        XCTAssertFalse(ix.accounts[1].isSigner)
        XCTAssertTrue(ix.accounts[1].isWritable)

        // owner: signer, not writable
        XCTAssertEqual(ix.accounts[2].publicKey, owner)
        XCTAssertTrue(ix.accounts[2].isSigner)
        XCTAssertFalse(ix.accounts[2].isWritable)
    }

    func testTransferProgramId() throws {
        let source = try SolanaPublicKey(data: Data(repeating: 1, count: 32))
        let destination = try SolanaPublicKey(data: Data(repeating: 2, count: 32))
        let owner = try SolanaPublicKey(data: Data(repeating: 3, count: 32))

        let ix = TokenProgram.transfer(source: source, destination: destination, owner: owner, amount: 100)

        XCTAssertEqual(ix.programId.base58, "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
    }

    func testCreateAssociatedTokenAccountAccounts() throws {
        let payer = try SolanaPublicKey(data: Data(repeating: 1, count: 32))
        let owner = try SolanaPublicKey(data: Data(repeating: 2, count: 32))
        let mint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

        let ix = try TokenProgram.createAssociatedTokenAccount(payer: payer, owner: owner, mint: mint)

        // ATA program as programId
        XCTAssertEqual(ix.programId.base58, "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")

        // Empty instruction data
        XCTAssertTrue(ix.data.isEmpty)

        // 6 accounts
        XCTAssertEqual(ix.accounts.count, 6)

        // payer: signer, writable
        XCTAssertEqual(ix.accounts[0].publicKey, payer)
        XCTAssertTrue(ix.accounts[0].isSigner)
        XCTAssertTrue(ix.accounts[0].isWritable)

        // ATA: writable, not signer
        let expectedATA = try SolanaPublicKey.associatedTokenAddress(owner: owner, mint: mint)
        XCTAssertEqual(ix.accounts[1].publicKey, expectedATA)
        XCTAssertFalse(ix.accounts[1].isSigner)
        XCTAssertTrue(ix.accounts[1].isWritable)

        // owner: not signer, not writable
        XCTAssertEqual(ix.accounts[2].publicKey, owner)
        XCTAssertFalse(ix.accounts[2].isSigner)
        XCTAssertFalse(ix.accounts[2].isWritable)

        // mint: not signer, not writable
        XCTAssertEqual(ix.accounts[3].publicKey, mint)
        XCTAssertFalse(ix.accounts[3].isSigner)
        XCTAssertFalse(ix.accounts[3].isWritable)

        // system program
        XCTAssertEqual(ix.accounts[4].publicKey.base58, "11111111111111111111111111111111")
        XCTAssertFalse(ix.accounts[4].isSigner)
        XCTAssertFalse(ix.accounts[4].isWritable)

        // token program
        XCTAssertEqual(ix.accounts[5].publicKey.base58, "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        XCTAssertFalse(ix.accounts[5].isSigner)
        XCTAssertFalse(ix.accounts[5].isWritable)
    }
}
