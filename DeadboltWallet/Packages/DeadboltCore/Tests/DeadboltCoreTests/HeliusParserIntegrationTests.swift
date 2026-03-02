import XCTest
@testable import DeadboltCore

/// P7-014: Transaction parser integration tests.
/// Tests parsing mock Helius Enhanced Transaction responses for known transaction types
/// and verifying correct TransactionHistoryEntry creation from each.
final class HeliusParserIntegrationTests: XCTestCase {

    // MARK: - Test 1: SOL transfer -> TransactionType.transfer

    func testParseSOLTransfer() throws {
        let json = """
        {
            "description": "3Kzyx transferred 1.5 SOL to 9WzD...",
            "type": "TRANSFER",
            "source": "SYSTEM_PROGRAM",
            "fee": 5000,
            "feePayer": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
            "signature": "4VrC1QZjP8V1u8Xp3YRHK7jBZqfqUwLdC5Xs4KNqtmqf9PoVf8JQJH7XSnPz5RPxPrJ7QNjGJMmh5pu6TyNFPZR",
            "slot": 290000000,
            "timestamp": 1710000000,
            "nativeTransfers": [
                {
                    "fromUserAccount": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
                    "toUserAccount": "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
                    "amount": 1500000000
                }
            ],
            "tokenTransfers": []
        }
        """.data(using: .utf8)!

        let helius = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)
        let entry = TransactionHistoryEntry(from: helius)

        XCTAssertEqual(entry.type, .transfer)
        XCTAssertEqual(entry.signature, "4VrC1QZjP8V1u8Xp3YRHK7jBZqfqUwLdC5Xs4KNqtmqf9PoVf8JQJH7XSnPz5RPxPrJ7QNjGJMmh5pu6TyNFPZR")
        XCTAssertEqual(entry.description, "3Kzyx transferred 1.5 SOL to 9WzD...")
        XCTAssertEqual(entry.timestamp, Date(timeIntervalSince1970: 1710000000))
        XCTAssertNotNil(entry.amount)
        XCTAssertTrue(entry.amount!.contains("SOL"), "Amount should mention SOL")
        XCTAssertTrue(entry.amount!.contains("1.5"), "Amount should contain 1.5")
        XCTAssertEqual(entry.nativeTransfers.count, 1)
        XCTAssertEqual(entry.nativeTransfers[0].amount, 1500000000)
        XCTAssertEqual(entry.tokenTransfers.count, 0)
    }

    // MARK: - Test 2: Token swap -> TransactionType.swap

    func testParseTokenSwap() throws {
        let json = """
        {
            "description": "3Kzyx swapped 500 USDC for 2.1 SOL via Jupiter",
            "type": "SWAP",
            "source": "JUPITER",
            "fee": 5000,
            "feePayer": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
            "signature": "2xPQr8bQJ5V6SFnHvXgjCZANmmKQQ2YtMRpLZBxK7Jfm",
            "slot": 290000100,
            "timestamp": 1710000100,
            "nativeTransfers": [
                {
                    "fromUserAccount": "JUPSomeProgramAddress111111111111111111111",
                    "toUserAccount": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
                    "amount": 2100000000
                }
            ],
            "tokenTransfers": [
                {
                    "fromUserAccount": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
                    "toUserAccount": "JUPSomeProgramAddress111111111111111111111",
                    "fromTokenAccount": "ATA_USDC_3Kzyx",
                    "toTokenAccount": "ATA_USDC_JUP",
                    "tokenAmount": 500.0,
                    "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
                }
            ]
        }
        """.data(using: .utf8)!

        let helius = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)
        let entry = TransactionHistoryEntry(from: helius)

        XCTAssertEqual(entry.type, .swap)
        XCTAssertEqual(entry.signature, "2xPQr8bQJ5V6SFnHvXgjCZANmmKQQ2YtMRpLZBxK7Jfm")
        XCTAssertNotNil(entry.amount)
        XCTAssertTrue(entry.amount!.contains("500"), "Amount should contain token amount")
        XCTAssertEqual(entry.tokenTransfers.count, 1)
        XCTAssertEqual(entry.tokenTransfers[0].mint, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
    }

    // MARK: - Test 3: Staking -> TransactionType.stake

    func testParseStakingTransaction() throws {
        let json = """
        {
            "description": "3Kzyx staked 10 SOL with Sanctum",
            "type": "STAKE",
            "source": "SANCTUM",
            "fee": 5000,
            "feePayer": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
            "signature": "5xMN3vK9YfrQgH2pL7dWhjCmZ8K4rQPbN",
            "slot": 290000200,
            "timestamp": 1710000200,
            "nativeTransfers": [
                {
                    "fromUserAccount": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
                    "toUserAccount": "StakePool11111111111111111111111111111111",
                    "amount": 10000000000
                }
            ],
            "tokenTransfers": []
        }
        """.data(using: .utf8)!

        let helius = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)
        let entry = TransactionHistoryEntry(from: helius)

        XCTAssertEqual(entry.type, .stake)
        XCTAssertNotNil(entry.amount)
        XCTAssertTrue(entry.amount!.contains("SOL"))
        XCTAssertEqual(entry.nativeTransfers.count, 1)
        XCTAssertEqual(entry.nativeTransfers[0].amount, 10000000000)
    }

    // MARK: - Test 4: NFT transfer -> TransactionType.nftTransfer

    func testParseNFTTransfer() throws {
        let json = """
        {
            "description": "3Kzyx transferred Mad Lad #1234 to 9WzD...",
            "type": "NFT_TRANSFER",
            "source": "METAPLEX",
            "fee": 5000,
            "feePayer": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
            "signature": "3hNFT7rJpG2vK9YfrQgH2pL7dWhjCmZ8K",
            "slot": 290000300,
            "timestamp": 1710000300,
            "nativeTransfers": [],
            "tokenTransfers": [
                {
                    "fromUserAccount": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
                    "toUserAccount": "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
                    "fromTokenAccount": "ATA_NFT_FROM",
                    "toTokenAccount": "ATA_NFT_TO",
                    "tokenAmount": 1.0,
                    "mint": "MadLad1234MintAddress11111111111111111111"
                }
            ]
        }
        """.data(using: .utf8)!

        let helius = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)
        let entry = TransactionHistoryEntry(from: helius)

        XCTAssertEqual(entry.type, .nftTransfer)
        XCTAssertEqual(entry.description, "3Kzyx transferred Mad Lad #1234 to 9WzD...")
        XCTAssertNotNil(entry.amount)
        XCTAssertTrue(entry.amount!.contains("1"), "NFT amount should be 1")
        XCTAssertEqual(entry.tokenTransfers.count, 1)
        XCTAssertEqual(entry.tokenTransfers[0].tokenAmount, 1.0)
    }

    // MARK: - Test 5: Unknown transaction type -> TransactionType.unknown

    func testParseUnknownTransactionType() throws {
        let json = """
        {
            "description": "Unknown program interaction",
            "type": "BORROW_FOX",
            "source": "SHARKY_FI",
            "fee": 5000,
            "feePayer": "3KzyxVSsghJHB1kgPE8oTgXgMgaGQcfvnuWfCwFPB99Y",
            "signature": "7xUnk9nVw2qM3kLpR",
            "slot": 290000400,
            "timestamp": 1710000400,
            "nativeTransfers": [],
            "tokenTransfers": []
        }
        """.data(using: .utf8)!

        let helius = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)
        let entry = TransactionHistoryEntry(from: helius)

        XCTAssertEqual(entry.type, .unknown)
        XCTAssertEqual(entry.description, "Unknown program interaction")
        XCTAssertNil(entry.amount, "Unknown transaction with no transfers should have nil amount")
        XCTAssertEqual(entry.nativeTransfers.count, 0)
        XCTAssertEqual(entry.tokenTransfers.count, 0)
    }

    // MARK: - Test 6: Batch parsing of mixed transaction types

    func testBatchParsingMixedTypes() throws {
        let json = """
        [
            {
                "description": "Transfer",
                "type": "TRANSFER",
                "source": "SYSTEM_PROGRAM",
                "fee": 5000,
                "feePayer": "sender1",
                "signature": "sig1",
                "slot": 100,
                "timestamp": 1710000000,
                "nativeTransfers": [{"fromUserAccount": "A", "toUserAccount": "B", "amount": 100000000}],
                "tokenTransfers": []
            },
            {
                "description": "Swap",
                "type": "SWAP",
                "source": "JUPITER",
                "fee": 5000,
                "feePayer": "sender2",
                "signature": "sig2",
                "slot": 101,
                "timestamp": 1710000100,
                "nativeTransfers": [],
                "tokenTransfers": [{"fromUserAccount": "A", "toUserAccount": "B", "fromTokenAccount": "C", "toTokenAccount": "D", "tokenAmount": 50.0, "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"}]
            },
            {
                "description": "Stake",
                "type": "STAKE",
                "source": "SANCTUM",
                "fee": 5000,
                "feePayer": "sender3",
                "signature": "sig3",
                "slot": 102,
                "timestamp": 1710000200,
                "nativeTransfers": [{"fromUserAccount": "A", "toUserAccount": "B", "amount": 5000000000}],
                "tokenTransfers": []
            },
            {
                "description": "NFT Sale",
                "type": "NFT_SALE",
                "source": "MAGIC_EDEN",
                "fee": 5000,
                "feePayer": "sender4",
                "signature": "sig4",
                "slot": 103,
                "timestamp": 1710000300,
                "nativeTransfers": [],
                "tokenTransfers": []
            },
            {
                "description": "Unknown",
                "type": "LOAN_REPAYMENT",
                "source": "SHARKY",
                "fee": 5000,
                "feePayer": "sender5",
                "signature": "sig5",
                "slot": 104,
                "timestamp": 1710000400,
                "nativeTransfers": [],
                "tokenTransfers": []
            }
        ]
        """.data(using: .utf8)!

        let transactions = try JSONDecoder().decode([HeliusEnhancedTransaction].self, from: json)
        XCTAssertEqual(transactions.count, 5)

        let entries = transactions.map { TransactionHistoryEntry(from: $0) }

        XCTAssertEqual(entries[0].type, .transfer)
        XCTAssertEqual(entries[0].signature, "sig1")
        XCTAssertNotNil(entries[0].amount)

        XCTAssertEqual(entries[1].type, .swap)
        XCTAssertEqual(entries[1].signature, "sig2")
        XCTAssertNotNil(entries[1].amount)

        XCTAssertEqual(entries[2].type, .stake)
        XCTAssertEqual(entries[2].signature, "sig3")
        XCTAssertNotNil(entries[2].amount)

        XCTAssertEqual(entries[3].type, .nftTransfer)
        XCTAssertEqual(entries[3].signature, "sig4")

        XCTAssertEqual(entries[4].type, .unknown)
        XCTAssertEqual(entries[4].signature, "sig5")
    }

    // MARK: - Test 7: Unstake maps to .stake

    func testUnstakeTypeMapsTostake() throws {
        let json = """
        {
            "description": "Unstaked 5 SOL",
            "type": "UNSTAKE",
            "source": "SANCTUM",
            "fee": 5000,
            "feePayer": "unstaker1",
            "signature": "unstakeSig1",
            "slot": 300000000,
            "timestamp": 1720000000,
            "nativeTransfers": [{"fromUserAccount": "Pool", "toUserAccount": "unstaker1", "amount": 5000000000}],
            "tokenTransfers": []
        }
        """.data(using: .utf8)!

        let helius = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)
        let entry = TransactionHistoryEntry(from: helius)

        XCTAssertEqual(entry.type, .stake, "UNSTAKE should map to .stake type")
        XCTAssertNotNil(entry.amount)
        XCTAssertTrue(entry.amount!.contains("SOL"))
    }
}
