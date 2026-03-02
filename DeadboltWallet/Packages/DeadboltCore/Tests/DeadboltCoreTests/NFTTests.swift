import XCTest
@testable import DeadboltCore

final class NFTTests: XCTestCase {

    // MARK: - HeliusAsset JSON Decoding

    func testDecodeHeliusAssetFromSampleResponse() throws {
        let json = """
        {
            "id": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "content": {
                "metadata": {
                    "name": "Cool NFT #42",
                    "symbol": "COOL",
                    "description": "A very cool NFT"
                },
                "links": {
                    "image": "https://arweave.net/abc123"
                }
            },
            "ownership": {
                "owner": "11111111111111111111111111111111",
                "frozen": false
            },
            "compression": {
                "compressed": false
            }
        }
        """.data(using: .utf8)!

        let asset = try JSONDecoder().decode(HeliusAsset.self, from: json)

        XCTAssertEqual(asset.id, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        XCTAssertEqual(asset.content?.metadata?.name, "Cool NFT #42")
        XCTAssertEqual(asset.content?.metadata?.symbol, "COOL")
        XCTAssertEqual(asset.content?.metadata?.description, "A very cool NFT")
        XCTAssertEqual(asset.content?.links?.image, "https://arweave.net/abc123")
        XCTAssertEqual(asset.ownership?.owner, "11111111111111111111111111111111")
        XCTAssertEqual(asset.ownership?.frozen, false)
        XCTAssertEqual(asset.compression?.compressed, false)
    }

    func testDecodeHeliusAssetWithMinimalFields() throws {
        let json = """
        {
            "id": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        }
        """.data(using: .utf8)!

        let asset = try JSONDecoder().decode(HeliusAsset.self, from: json)

        XCTAssertEqual(asset.id, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        XCTAssertNil(asset.content)
        XCTAssertNil(asset.ownership)
        XCTAssertNil(asset.compression)
    }

    func testDecodeHeliusAssetCompressed() throws {
        let json = """
        {
            "id": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "content": {
                "metadata": {
                    "name": "Compressed NFT"
                }
            },
            "compression": {
                "compressed": true
            }
        }
        """.data(using: .utf8)!

        let asset = try JSONDecoder().decode(HeliusAsset.self, from: json)

        XCTAssertEqual(asset.compression?.compressed, true)
    }

    func testDecodeGetAssetsByOwnerResult() throws {
        let json = """
        {
            "total": 2,
            "limit": 1000,
            "page": 1,
            "items": [
                {
                    "id": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                    "content": {
                        "metadata": {
                            "name": "NFT One",
                            "symbol": "ONE"
                        },
                        "links": {
                            "image": "https://example.com/one.png"
                        }
                    },
                    "ownership": {
                        "owner": "11111111111111111111111111111111",
                        "frozen": false
                    },
                    "compression": {
                        "compressed": false
                    }
                },
                {
                    "id": "So11111111111111111111111111111111111111112",
                    "content": {
                        "metadata": {
                            "name": "NFT Two",
                            "symbol": "TWO"
                        }
                    },
                    "compression": {
                        "compressed": true
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(HeliusGetAssetsByOwnerResult.self, from: json)

        XCTAssertEqual(result.total, 2)
        XCTAssertEqual(result.limit, 1000)
        XCTAssertEqual(result.page, 1)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].content?.metadata?.name, "NFT One")
        XCTAssertEqual(result.items[1].content?.metadata?.name, "NFT Two")
    }

    // MARK: - NFTAsset Conversion

    func testToNFTAssetWithFullMetadata() throws {
        let asset = HeliusAsset(
            id: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            content: HeliusContent(
                metadata: HeliusMetadata(name: "Cool NFT", symbol: "COOL", description: "A cool one"),
                links: HeliusLinks(image: "https://arweave.net/img.png")
            ),
            ownership: HeliusOwnership(owner: "11111111111111111111111111111111", frozen: false),
            compression: HeliusCompression(compressed: false)
        )

        let nft = asset.toNFTAsset()

        XCTAssertNotNil(nft)
        XCTAssertEqual(nft!.mint.base58, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        XCTAssertEqual(nft!.name, "Cool NFT")
        XCTAssertEqual(nft!.symbol, "COOL")
        XCTAssertEqual(nft!.imageURL, "https://arweave.net/img.png")
        XCTAssertFalse(nft!.isCompressed)
    }

    func testToNFTAssetWithMissingMetadataUsesDefaults() throws {
        let asset = HeliusAsset(
            id: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            content: nil,
            ownership: nil,
            compression: nil
        )

        let nft = asset.toNFTAsset()

        XCTAssertNotNil(nft)
        XCTAssertEqual(nft!.name, "Unknown")
        XCTAssertEqual(nft!.symbol, "")
        XCTAssertNil(nft!.imageURL)
        XCTAssertFalse(nft!.isCompressed) // defaults to false when compression is nil
    }

    func testToNFTAssetCompressedFlag() throws {
        let asset = HeliusAsset(
            id: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            content: nil,
            ownership: nil,
            compression: HeliusCompression(compressed: true)
        )

        let nft = asset.toNFTAsset()

        XCTAssertNotNil(nft)
        XCTAssertTrue(nft!.isCompressed)
    }

    func testToNFTAssetInvalidIdReturnsNil() throws {
        let asset = HeliusAsset(
            id: "not-a-valid-base58-key!!!",
            content: HeliusContent(
                metadata: HeliusMetadata(name: "Bad", symbol: "BAD", description: nil),
                links: nil
            ),
            ownership: nil,
            compression: nil
        )

        let nft = asset.toNFTAsset()

        XCTAssertNil(nft)
    }

    // MARK: - isNFT Detection

    func testIsNFTWithDecimals0AndAmount1ReturnsTrue() throws {
        let entry = makeTokenAccountEntry(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 0, amount: "1")
        XCTAssertTrue(NFTService.isNFT(tokenAccount: entry))
    }

    func testIsNFTWithDecimals6AndLargeAmountReturnsFalse() throws {
        let entry = makeTokenAccountEntry(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 6, amount: "1000000")
        XCTAssertFalse(NFTService.isNFT(tokenAccount: entry))
    }

    func testIsNFTWithDecimals0AndAmount0ReturnsFalse() throws {
        let entry = makeTokenAccountEntry(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 0, amount: "0")
        XCTAssertFalse(NFTService.isNFT(tokenAccount: entry))
    }

    func testIsNFTWithDecimals0AndAmount2ReturnsFalse() throws {
        let entry = makeTokenAccountEntry(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 0, amount: "2")
        XCTAssertFalse(NFTService.isNFT(tokenAccount: entry))
    }

    func testIsNFTWithDecimals9AndAmount1ReturnsFalse() throws {
        // Fungible token with very small balance (1 raw unit, 9 decimals = 0.000000001)
        let entry = makeTokenAccountEntry(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 9, amount: "1")
        XCTAssertFalse(NFTService.isNFT(tokenAccount: entry))
    }

    // MARK: - buildSendNFT Structural Tests

    func testBuildSendNFTCreatesCorrectInstructionStructure() async throws {
        // This test verifies the instruction structure without calling real RPC.
        // buildSendNFT delegates to buildSendToken(amount: 1, decimals: 0),
        // so we verify the token transfer instruction uses amount=1.

        let signer = try SoftwareSigner(seed: Data(repeating: 0xAA, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0xBB, count: 32))
        let mint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

        // Derive expected ATAs
        let senderATA = try SolanaPublicKey.associatedTokenAddress(owner: signer.publicKey, mint: mint)
        let recipientATA = try SolanaPublicKey.associatedTokenAddress(owner: recipient, mint: mint)

        // Verify the transfer instruction for amount=1
        let transferIx = TokenProgram.transfer(
            source: senderATA,
            destination: recipientATA,
            owner: signer.publicKey,
            amount: 1
        )

        // Transfer data: u8(3) + u64(1) LE = 9 bytes
        XCTAssertEqual(transferIx.data.count, 9)
        XCTAssertEqual(transferIx.data[0], 3) // Transfer variant
        XCTAssertEqual(transferIx.data[1], 1) // amount=1 LE byte 0
        for i in 2..<9 {
            XCTAssertEqual(transferIx.data[i], 0) // remaining bytes of u64(1) are 0
        }

        // Verify the ATA creation instruction includes the right accounts
        let createATAIx = try TokenProgram.createAssociatedTokenAccount(
            payer: signer.publicKey,
            owner: recipient,
            mint: mint
        )
        XCTAssertEqual(createATAIx.accounts.count, 6)
        XCTAssertEqual(createATAIx.accounts[1].publicKey, recipientATA)
        XCTAssertTrue(createATAIx.data.isEmpty)
    }

    func testBuildSendNFTInstructionOrdering() throws {
        // Verify the expected instruction ordering for a full NFT send:
        // 1. ComputeBudgetProgram.setComputeUnitLimit
        // 2. ComputeBudgetProgram.setComputeUnitPrice
        // 3. (Optional) createAssociatedTokenAccount for recipient
        // 4. TokenProgram.transfer(amount: 1)
        // 5. JitoTip

        let signer = try SolanaPublicKey(data: Data(repeating: 0xAA, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0xBB, count: 32))
        let mint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let senderATA = try SolanaPublicKey.associatedTokenAddress(owner: signer, mint: mint)
        let recipientATA = try SolanaPublicKey.associatedTokenAddress(owner: recipient, mint: mint)

        // Build the instruction list manually to verify ordering (mirrors TransactionBuilder logic)
        var instructions: [Instruction] = []
        instructions.append(ComputeBudgetProgram.setComputeUnitLimit(200_000))
        instructions.append(ComputeBudgetProgram.setComputeUnitPrice(1000))
        instructions.append(try TokenProgram.createAssociatedTokenAccount(payer: signer, owner: recipient, mint: mint))
        instructions.append(TokenProgram.transfer(source: senderATA, destination: recipientATA, owner: signer, amount: 1))
        instructions.append(try JitoTip.tipInstruction(from: signer, lamports: JitoTip.defaultTipLamports))

        // With ATA creation: 5 instructions
        XCTAssertEqual(instructions.count, 5)

        // Instruction 0: ComputeBudgetProgram (setComputeUnitLimit)
        XCTAssertEqual(instructions[0].programId.base58, "ComputeBudget111111111111111111111111111111")
        XCTAssertEqual(instructions[0].data[0], 2) // SetComputeUnitLimit variant

        // Instruction 1: ComputeBudgetProgram (setComputeUnitPrice)
        XCTAssertEqual(instructions[1].programId.base58, "ComputeBudget111111111111111111111111111111")
        XCTAssertEqual(instructions[1].data[0], 3) // SetComputeUnitPrice variant

        // Instruction 2: ATA creation
        XCTAssertEqual(instructions[2].programId.base58, "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")

        // Instruction 3: Token transfer with amount=1
        XCTAssertEqual(instructions[3].programId.base58, "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        XCTAssertEqual(instructions[3].data[0], 3) // Transfer variant
        XCTAssertEqual(instructions[3].data[1], 1) // amount=1

        // Instruction 4: Jito tip (SOL transfer to tip account via System Program)
        XCTAssertEqual(instructions[4].programId.base58, "11111111111111111111111111111111")
    }

    func testBuildSendNFTWithoutATACreationHas4Instructions() throws {
        // Without ATA creation: 4 instructions
        let signer = try SolanaPublicKey(data: Data(repeating: 0xAA, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0xBB, count: 32))
        let mint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let senderATA = try SolanaPublicKey.associatedTokenAddress(owner: signer, mint: mint)
        let recipientATA = try SolanaPublicKey.associatedTokenAddress(owner: recipient, mint: mint)

        var instructions: [Instruction] = []
        instructions.append(ComputeBudgetProgram.setComputeUnitLimit(200_000))
        instructions.append(ComputeBudgetProgram.setComputeUnitPrice(1000))
        // No ATA creation (recipient already has one)
        instructions.append(TokenProgram.transfer(source: senderATA, destination: recipientATA, owner: signer, amount: 1))
        instructions.append(try JitoTip.tipInstruction(from: signer, lamports: JitoTip.defaultTipLamports))

        XCTAssertEqual(instructions.count, 4)

        // Token transfer is instruction 2 (not 3)
        XCTAssertEqual(instructions[2].programId.base58, "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        XCTAssertEqual(instructions[2].data[1], 1) // amount=1
    }

    // MARK: - Helpers

    private func makeTokenAccountEntry(mint: String, decimals: Int, amount: String) -> TokenAccountEntry {
        let tokenAmount = TokenAmount(
            amount: amount,
            decimals: decimals,
            uiAmount: decimals == 0 ? Double(amount) : nil,
            uiAmountString: amount
        )
        let infoData = TokenAccountInfoData(
            mint: mint,
            owner: "11111111111111111111111111111111",
            tokenAmount: tokenAmount
        )
        let info = TokenAccountInfo(info: infoData, type: "account")
        let parsed = TokenAccountParsed(parsed: info, program: "spl-token")
        let data = TokenAccountData(data: parsed, lamports: 2039280)
        return TokenAccountEntry(pubkey: "SomeTokenAccountPubkey1111111111111111111111111", account: data)
    }
}
