import XCTest
@testable import DeadboltCore

final class PDATests: XCTestCase {

    // MARK: - findProgramAddress basics

    func testFindProgramAddressReturnsValidPDA() throws {
        let programId = try SolanaPublicKey(base58: "11111111111111111111111111111111")
        let seed = Data("test".utf8)

        let (address, bump) = try SolanaPublicKey.findProgramAddress(seeds: [seed], programId: programId)

        // Bump should be <= 255
        XCTAssertTrue(bump <= 255)

        // Result should be 32 bytes
        XCTAssertEqual(address.data.count, 32)

        // The PDA should NOT be on the Ed25519 curve (verified by our own check)
        XCTAssertFalse(Ed25519CurveCheck.isOnCurve(address.data))
    }

    func testFindProgramAddressDeterministic() throws {
        let programId = try SolanaPublicKey(base58: "11111111111111111111111111111111")
        let seed = Data("hello".utf8)

        let (address1, bump1) = try SolanaPublicKey.findProgramAddress(seeds: [seed], programId: programId)
        let (address2, bump2) = try SolanaPublicKey.findProgramAddress(seeds: [seed], programId: programId)

        XCTAssertEqual(address1, address2)
        XCTAssertEqual(bump1, bump2)
    }

    func testFindProgramAddressDifferentSeedsProduceDifferentAddresses() throws {
        let programId = try SolanaPublicKey(base58: "11111111111111111111111111111111")

        let (address1, _) = try SolanaPublicKey.findProgramAddress(seeds: [Data("seed1".utf8)], programId: programId)
        let (address2, _) = try SolanaPublicKey.findProgramAddress(seeds: [Data("seed2".utf8)], programId: programId)

        XCTAssertNotEqual(address1, address2)
    }

    func testPDASeedTooLongThrows() throws {
        let programId = try SolanaPublicKey(base58: "11111111111111111111111111111111")
        let longSeed = Data(repeating: 0xAB, count: 33)

        XCTAssertThrowsError(try SolanaPublicKey.findProgramAddress(seeds: [longSeed], programId: programId))
    }

    func testMultipleSeeds() throws {
        let programId = try SolanaPublicKey(base58: "11111111111111111111111111111111")
        let seed1 = Data("first".utf8)
        let seed2 = Data("second".utf8)

        let (address, bump) = try SolanaPublicKey.findProgramAddress(seeds: [seed1, seed2], programId: programId)

        XCTAssertEqual(address.data.count, 32)
        XCTAssertTrue(bump <= 255)
        XCTAssertFalse(Ed25519CurveCheck.isOnCurve(address.data))
    }

    func testCreateProgramAddressWithBumpRecreatesPDA() throws {
        let programId = try SolanaPublicKey(base58: "11111111111111111111111111111111")
        let seed = Data("test".utf8)

        let (address, bump) = try SolanaPublicKey.findProgramAddress(seeds: [seed], programId: programId)

        // Recreating with the same seeds + bump should produce the same address
        let recreated = try SolanaPublicKey.createProgramAddress(
            seeds: [seed, Data([bump])],
            programId: programId
        )
        XCTAssertEqual(address, recreated)
    }

    // MARK: - ATA derivation

    func testATADerivationForKnownVector() throws {
        let owner = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let usdcMint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

        let ata = try SolanaPublicKey.associatedTokenAddress(owner: owner, mint: usdcMint)

        // The ATA should be a valid 32-byte key
        XCTAssertEqual(ata.data.count, 32)

        // The ATA should NOT be on the Ed25519 curve (it's a PDA)
        XCTAssertFalse(Ed25519CurveCheck.isOnCurve(ata.data))

        // Verify the ATA is deterministic
        let ata2 = try SolanaPublicKey.associatedTokenAddress(owner: owner, mint: usdcMint)
        XCTAssertEqual(ata, ata2)
    }

    func testATADerivationDifferentOwnersProduceDifferentATAs() throws {
        let owner1 = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let owner2 = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let mint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

        let ata1 = try SolanaPublicKey.associatedTokenAddress(owner: owner1, mint: mint)
        let ata2 = try SolanaPublicKey.associatedTokenAddress(owner: owner2, mint: mint)

        XCTAssertNotEqual(ata1, ata2)
    }

    func testATADerivationDifferentMintsProduceDifferentATAs() throws {
        let owner = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let usdc = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let usdt = try SolanaPublicKey(base58: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB")

        let ata1 = try SolanaPublicKey.associatedTokenAddress(owner: owner, mint: usdc)
        let ata2 = try SolanaPublicKey.associatedTokenAddress(owner: owner, mint: usdt)

        XCTAssertNotEqual(ata1, ata2)
    }

    func testATAUsesCorrectSeeds() throws {
        // Manually compute the PDA using findProgramAddress with ATA seeds
        // and verify it matches associatedTokenAddress
        let owner = try SolanaPublicKey(data: Data(repeating: 0x05, count: 32))
        let mint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let tokenProgramId = try SolanaPublicKey(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        let ataProgramId = try SolanaPublicKey(base58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")

        let (manualPDA, _) = try SolanaPublicKey.findProgramAddress(
            seeds: [owner.data, tokenProgramId.data, mint.data],
            programId: ataProgramId
        )

        let ata = try SolanaPublicKey.associatedTokenAddress(owner: owner, mint: mint)

        XCTAssertEqual(manualPDA, ata)
    }

    // MARK: - Known ATA vector

    func testATAKnownVector() throws {
        // Wallet: 7fUAJdStEuGbc3sM84cKRL6yYaaSstyLSU4ve21asR2r
        // USDC mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
        // Computed ATA via our algorithm (verified against Solana PDA spec)
        let wallet = try SolanaPublicKey(base58: "7fUAJdStEuGbc3sM84cKRL6yYaaSstyLSU4ve21asR2r")
        let usdcMint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

        let ata = try SolanaPublicKey.associatedTokenAddress(owner: wallet, mint: usdcMint)

        // Verify the ATA is a valid PDA (not on curve)
        XCTAssertFalse(Ed25519CurveCheck.isOnCurve(ata.data))

        // Snapshot test: record the deterministic result
        // This value is: SHA256(owner + tokenProgram + mint + ataProgramId + "ProgramDerivedAddress") with bump
        XCTAssertEqual(ata.base58, "FEEHnCYLSjT7QZJvNoNiuFABCpAwvvZjZ4ak5dAaU636")
    }

    // MARK: - Ed25519 on-curve check

    func testKnownOnCurvePoint() throws {
        // A valid Ed25519 public key (from a known keypair) should be on-curve
        // Ed25519 base point y-coordinate (standard generator point):
        // 4/5 mod p, with x = positive root
        // The base point in compressed form:
        let basePointBytes: [UInt8] = [
            0x58, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
            0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
            0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
            0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
        ]
        XCTAssertTrue(Ed25519CurveCheck.isOnCurve(Data(basePointBytes)))
    }

    func testIdentityPointIsOnCurve() throws {
        // The identity point (neutral element) has y = 1, x = 0
        // Compressed form: little-endian encoding of 1
        var identityBytes = [UInt8](repeating: 0, count: 32)
        identityBytes[0] = 1
        XCTAssertTrue(Ed25519CurveCheck.isOnCurve(Data(identityBytes)))
    }

    func testRandomBytesUsuallyNotOnCurve() throws {
        // Most random 32-byte values should NOT be valid Ed25519 points
        // (roughly 50% chance any random y-coordinate has a valid x)
        // Test with several known off-curve values
        var offCurveCount = 0
        for i: UInt8 in 0..<20 {
            var bytes = Data(repeating: i, count: 32)
            bytes[31] = 0x80 | i // Set high bit to make it more likely off-curve
            if !Ed25519CurveCheck.isOnCurve(bytes) {
                offCurveCount += 1
            }
        }
        // At least some should be off-curve
        XCTAssertTrue(offCurveCount > 0)
    }
}
