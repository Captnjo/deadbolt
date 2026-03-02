import XCTest
@testable import DeadboltCore

final class HeliusEnhancedTests: XCTestCase {

    // MARK: - JSON Decoding

    func testHeliusEnhancedTransactionDecoding() throws {
        let json = """
        {
            "description": "HXkm... transferred 0.5 SOL to 9WzD...",
            "type": "TRANSFER",
            "source": "SYSTEM_PROGRAM",
            "fee": 5000,
            "feePayer": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
            "signature": "3nVfqGG8o46MWAZ2nUQi1TiJxXgWjkmgZsDBCkJwn4bVxp7iUB7LhZe5N1ghMf8aQyYBg5CtEDVU9d73TJZw2Dpf",
            "slot": 245000000,
            "timestamp": 1700000000,
            "nativeTransfers": [
                {
                    "fromUserAccount": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
                    "toUserAccount": "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
                    "amount": 500000000
                }
            ],
            "tokenTransfers": []
        }
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)

        XCTAssertEqual(tx.description, "HXkm... transferred 0.5 SOL to 9WzD...")
        XCTAssertEqual(tx.type, "TRANSFER")
        XCTAssertEqual(tx.source, "SYSTEM_PROGRAM")
        XCTAssertEqual(tx.fee, 5000)
        XCTAssertEqual(tx.feePayer, "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX")
        XCTAssertEqual(tx.signature, "3nVfqGG8o46MWAZ2nUQi1TiJxXgWjkmgZsDBCkJwn4bVxp7iUB7LhZe5N1ghMf8aQyYBg5CtEDVU9d73TJZw2Dpf")
        XCTAssertEqual(tx.slot, 245000000)
        XCTAssertEqual(tx.timestamp, 1700000000)

        XCTAssertEqual(tx.nativeTransfers?.count, 1)
        XCTAssertEqual(tx.nativeTransfers?[0].fromUserAccount, "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX")
        XCTAssertEqual(tx.nativeTransfers?[0].toUserAccount, "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        XCTAssertEqual(tx.nativeTransfers?[0].amount, 500000000)

        XCTAssertEqual(tx.tokenTransfers?.count, 0)
    }

    func testHeliusTokenTransferDecoding() throws {
        let json = """
        {
            "description": "Swapped 100 USDC for 0.4 SOL",
            "type": "SWAP",
            "source": "JUPITER",
            "fee": 5000,
            "feePayer": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
            "signature": "5abc123",
            "slot": 245000001,
            "timestamp": 1700000100,
            "nativeTransfers": [],
            "tokenTransfers": [
                {
                    "fromUserAccount": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
                    "toUserAccount": "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
                    "fromTokenAccount": "ATokenAcc1",
                    "toTokenAccount": "ATokenAcc2",
                    "tokenAmount": 100.0,
                    "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
                }
            ]
        }
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)

        XCTAssertEqual(tx.type, "SWAP")
        XCTAssertEqual(tx.source, "JUPITER")
        XCTAssertEqual(tx.tokenTransfers?.count, 1)

        let tokenTransfer = tx.tokenTransfers![0]
        XCTAssertEqual(tokenTransfer.fromUserAccount, "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX")
        XCTAssertEqual(tokenTransfer.toUserAccount, "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        XCTAssertEqual(tokenTransfer.tokenAmount, 100.0)
        XCTAssertEqual(tokenTransfer.mint, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
    }

    func testHeliusNullableFieldsDecoding() throws {
        let json = """
        {
            "description": "Unknown transaction",
            "type": "UNKNOWN",
            "source": "UNKNOWN",
            "fee": 5000,
            "feePayer": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
            "signature": "abc123",
            "slot": 100,
            "timestamp": 1700000000
        }
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)

        XCTAssertNil(tx.nativeTransfers)
        XCTAssertNil(tx.tokenTransfers)
    }

    // MARK: - TransactionHistoryEntry creation

    func testHistoryEntryFromHeliusTransfer() throws {
        let helius = HeliusEnhancedTransaction(
            description: "Sent 0.5 SOL to 9WzD...",
            type: "TRANSFER",
            source: "SYSTEM_PROGRAM",
            fee: 5000,
            feePayer: "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
            signature: "sig123",
            slot: 245000000,
            timestamp: 1700000000,
            nativeTransfers: [
                HeliusNativeTransfer(
                    fromUserAccount: "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
                    toUserAccount: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
                    amount: 500_000_000
                ),
            ],
            tokenTransfers: nil
        )

        let entry = TransactionHistoryEntry(from: helius)

        XCTAssertEqual(entry.signature, "sig123")
        XCTAssertEqual(entry.type, .transfer)
        XCTAssertEqual(entry.description, "Sent 0.5 SOL to 9WzD...")
        XCTAssertEqual(entry.timestamp, Date(timeIntervalSince1970: 1700000000))
        XCTAssertNotNil(entry.amount)
        XCTAssertTrue(entry.amount!.contains("SOL"))
        XCTAssertEqual(entry.nativeTransfers.count, 1)
    }

    func testHistoryEntryFromHeliusSwap() throws {
        let helius = HeliusEnhancedTransaction(
            description: "Swapped 100 USDC for 0.4 SOL",
            type: "SWAP",
            source: "JUPITER",
            fee: 5000,
            feePayer: "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
            signature: "sig456",
            slot: 245000001,
            timestamp: 1700000100,
            nativeTransfers: nil,
            tokenTransfers: [
                HeliusTokenTransfer(
                    fromUserAccount: "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
                    toUserAccount: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
                    fromTokenAccount: "ATA1",
                    toTokenAccount: "ATA2",
                    tokenAmount: 100.0,
                    mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
                ),
            ]
        )

        let entry = TransactionHistoryEntry(from: helius)

        XCTAssertEqual(entry.signature, "sig456")
        XCTAssertEqual(entry.type, .swap)
        XCTAssertNotNil(entry.amount)
        XCTAssertTrue(entry.amount!.contains("100"))
        XCTAssertEqual(entry.tokenTransfers.count, 1)
    }

    // MARK: - TransactionType classification

    func testTransactionTypeTransfer() {
        XCTAssertEqual(TransactionType(heliusType: "TRANSFER"), .transfer)
    }

    func testTransactionTypeSwap() {
        XCTAssertEqual(TransactionType(heliusType: "SWAP"), .swap)
    }

    func testTransactionTypeStake() {
        XCTAssertEqual(TransactionType(heliusType: "STAKE"), .stake)
        XCTAssertEqual(TransactionType(heliusType: "UNSTAKE"), .stake)
    }

    func testTransactionTypeNFT() {
        XCTAssertEqual(TransactionType(heliusType: "NFT_TRANSFER"), .nftTransfer)
        XCTAssertEqual(TransactionType(heliusType: "NFT_SALE"), .nftTransfer)
        XCTAssertEqual(TransactionType(heliusType: "NFT_LISTING"), .nftTransfer)
        XCTAssertEqual(TransactionType(heliusType: "NFT_MINT"), .nftTransfer)
        XCTAssertEqual(TransactionType(heliusType: "COMPRESSED_NFT_TRANSFER"), .nftTransfer)
        XCTAssertEqual(TransactionType(heliusType: "COMPRESSED_NFT_MINT"), .nftTransfer)
    }

    func testTransactionTypeUnknown() {
        XCTAssertEqual(TransactionType(heliusType: "SOME_RANDOM_TYPE"), .unknown)
        XCTAssertEqual(TransactionType(heliusType: ""), .unknown)
    }

    func testTransactionTypeCaseInsensitive() {
        XCTAssertEqual(TransactionType(heliusType: "transfer"), .transfer)
        XCTAssertEqual(TransactionType(heliusType: "Transfer"), .transfer)
        XCTAssertEqual(TransactionType(heliusType: "swap"), .swap)
    }

    // MARK: - Multiple transactions decoding

    func testMultipleTransactionsDecoding() throws {
        let json = """
        [
            {
                "description": "Sent SOL",
                "type": "TRANSFER",
                "source": "SYSTEM_PROGRAM",
                "fee": 5000,
                "feePayer": "sender1",
                "signature": "sig1",
                "slot": 100,
                "timestamp": 1700000000,
                "nativeTransfers": [],
                "tokenTransfers": []
            },
            {
                "description": "Swapped tokens",
                "type": "SWAP",
                "source": "JUPITER",
                "fee": 5000,
                "feePayer": "sender2",
                "signature": "sig2",
                "slot": 101,
                "timestamp": 1700000100,
                "nativeTransfers": [],
                "tokenTransfers": []
            }
        ]
        """.data(using: .utf8)!

        let txs = try JSONDecoder().decode([HeliusEnhancedTransaction].self, from: json)
        XCTAssertEqual(txs.count, 2)
        XCTAssertEqual(txs[0].type, "TRANSFER")
        XCTAssertEqual(txs[1].type, "SWAP")
    }

    // MARK: - SignatureInfo decoding

    func testSignatureInfoDecoding() throws {
        let json = """
        {
            "signature": "5abc123def",
            "slot": 245000000,
            "blockTime": 1700000000,
            "err": null,
            "memo": null,
            "confirmationStatus": "finalized"
        }
        """.data(using: .utf8)!

        let info = try JSONDecoder().decode(SignatureInfo.self, from: json)
        XCTAssertEqual(info.signature, "5abc123def")
        XCTAssertEqual(info.slot, 245000000)
        XCTAssertEqual(info.blockTime, 1700000000)
        XCTAssertNil(info.err)
        XCTAssertNil(info.memo)
        XCTAssertEqual(info.confirmationStatus, "finalized")
    }

    // MARK: - HeliusEnhancedTransactionsRequest encoding

    func testRequestBodyEncoding() throws {
        let request = HeliusEnhancedTransactionsRequest(
            transactions: ["sig1", "sig2", "sig3"]
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let transactions = json["transactions"] as! [String]
        XCTAssertEqual(transactions, ["sig1", "sig2", "sig3"])
    }
}
