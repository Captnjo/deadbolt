import XCTest
@testable import DeadboltCore

/// P9-005: Comprehensive unit tests for the Network module.
/// Covers RPC type decoding, JupiterTypes, SanctumTypes, HeliusTypes JSON decoding,
/// and error handling for malformed JSON.
final class NetworkComprehensiveTests: XCTestCase {

    // MARK: - RPC Type Decoding: BalanceResult

    func testBalanceResultDecoding() throws {
        let json = """
        {"value": 1000000000}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(BalanceResult.self, from: json)
        XCTAssertEqual(result.value, 1_000_000_000)
    }

    func testBalanceResultZero() throws {
        let json = """
        {"value": 0}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(BalanceResult.self, from: json)
        XCTAssertEqual(result.value, 0)
    }

    // MARK: - RPC Type Decoding: BlockhashResult

    func testBlockhashResultDecoding() throws {
        let json = """
        {
            "value": {
                "blockhash": "GWWy2aAev5X3TMRVwdw8W2KMN3dyVrHrQMZukGTf9R1A",
                "lastValidBlockHeight": 151600000
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(BlockhashResult.self, from: json)
        XCTAssertEqual(result.value.blockhash, "GWWy2aAev5X3TMRVwdw8W2KMN3dyVrHrQMZukGTf9R1A")
        XCTAssertEqual(result.value.lastValidBlockHeight, 151600000)
    }

    // MARK: - RPC Type Decoding: TokenAccountsResult

    func testTokenAccountsResultDecoding() throws {
        let json = """
        {
            "value": [
                {
                    "pubkey": "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
                    "account": {
                        "data": {
                            "parsed": {
                                "info": {
                                    "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                                    "owner": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
                                    "tokenAmount": {
                                        "amount": "1000000",
                                        "decimals": 6,
                                        "uiAmount": 1.0,
                                        "uiAmountString": "1"
                                    }
                                },
                                "type": "account"
                            },
                            "program": "spl-token"
                        },
                        "lamports": 2039280
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(TokenAccountsResult.self, from: json)
        XCTAssertEqual(result.value.count, 1)
        XCTAssertEqual(result.value[0].pubkey, "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        XCTAssertEqual(result.value[0].account.data.parsed.info.mint, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        XCTAssertEqual(result.value[0].account.data.parsed.info.tokenAmount.amount, "1000000")
        XCTAssertEqual(result.value[0].account.data.parsed.info.tokenAmount.decimals, 6)
        XCTAssertEqual(result.value[0].account.data.parsed.info.tokenAmount.uiAmount, 1.0)
    }

    func testTokenAccountsResultEmpty() throws {
        let json = """
        {"value": []}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(TokenAccountsResult.self, from: json)
        XCTAssertEqual(result.value.count, 0)
    }

    // MARK: - RPC Type Decoding: SignatureStatusesResult

    func testSignatureStatusesResultDecoding() throws {
        let json = """
        {
            "value": [
                {
                    "slot": 245000000,
                    "confirmations": 10,
                    "err": null,
                    "confirmationStatus": "confirmed"
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(SignatureStatusesResult.self, from: json)
        XCTAssertEqual(result.value.count, 1)
        XCTAssertNotNil(result.value[0])
        XCTAssertEqual(result.value[0]?.slot, 245000000)
        XCTAssertEqual(result.value[0]?.confirmations, 10)
        XCTAssertNil(result.value[0]?.err)
        XCTAssertEqual(result.value[0]?.confirmationStatus, "confirmed")
    }

    func testSignatureStatusesResultWithNull() throws {
        let json = """
        {
            "value": [null]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(SignatureStatusesResult.self, from: json)
        XCTAssertEqual(result.value.count, 1)
        XCTAssertNil(result.value[0])
    }

    func testSignatureStatusesResultWithError() throws {
        let json = """
        {
            "value": [
                {
                    "slot": 245000000,
                    "confirmations": null,
                    "err": "AccountNotFound",
                    "confirmationStatus": "processed"
                }
            ]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(SignatureStatusesResult.self, from: json)
        XCTAssertNotNil(result.value[0]?.err)
    }

    // MARK: - RPC Type Decoding: SimulateResult

    func testSimulateResultSuccess() throws {
        let json = """
        {
            "value": {
                "err": null,
                "logs": [
                    "Program 11111111111111111111111111111111 invoke [1]",
                    "Program 11111111111111111111111111111111 success"
                ],
                "unitsConsumed": 150
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(SimulateResult.self, from: json)
        XCTAssertNil(result.value.err)
        XCTAssertEqual(result.value.logs?.count, 2)
        XCTAssertEqual(result.value.unitsConsumed, 150)
    }

    func testSimulateResultWithError() throws {
        let json = """
        {
            "value": {
                "err": "InsufficientFundsForFee",
                "logs": null,
                "unitsConsumed": 0
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(SimulateResult.self, from: json)
        XCTAssertNotNil(result.value.err)
    }

    // MARK: - RPC Response Envelope

    func testRPCResponseEnvelope() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "result": {"value": 5000000}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RPCResponse<BalanceResult>.self, from: json)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 1)
        XCTAssertEqual(response.result?.value, 5000000)
    }

    // MARK: - JupiterTypes

    func testJupiterQuoteWithNullPriceImpact() throws {
        let json = """
        {
            "inputMint": "So11111111111111111111111111111111111111112",
            "inAmount": "100",
            "outputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "outAmount": "2",
            "otherAmountThreshold": "1",
            "swapMode": "ExactIn",
            "slippageBps": 100,
            "priceImpactPct": null,
            "routePlan": []
        }
        """.data(using: .utf8)!

        let quote = try JSONDecoder().decode(JupiterQuote.self, from: json)
        XCTAssertNil(quote.priceImpactPct)
        XCTAssertEqual(quote.routePlan.count, 0)
    }

    func testJupiterSwapInstructionsWithAllFields() throws {
        let json = """
        {
            "tokenLedgerInstruction": {
                "programId": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
                "accounts": [],
                "data": "AA=="
            },
            "computeBudgetInstructions": [
                {
                    "programId": "ComputeBudget111111111111111111111111111111",
                    "accounts": [],
                    "data": "AgDwAQ=="
                }
            ],
            "setupInstructions": [],
            "swapInstruction": {
                "programId": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
                "accounts": [
                    {"pubkey": "UserWallet11111111111111111111111111111111", "isSigner": true, "isWritable": true}
                ],
                "data": "AQ=="
            },
            "cleanupInstruction": {
                "programId": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
                "accounts": [],
                "data": "Ag=="
            },
            "addressLookupTableAddresses": ["HyaB3W9q6XdA5xwpU4XnSZV94htfmbmqJXZcEbRaJutt"]
        }
        """.data(using: .utf8)!

        let swapIx = try JSONDecoder().decode(JupiterSwapInstructions.self, from: json)
        XCTAssertNotNil(swapIx.tokenLedgerInstruction)
        XCTAssertEqual(swapIx.computeBudgetInstructions.count, 1)
        XCTAssertNotNil(swapIx.cleanupInstruction)
        XCTAssertEqual(swapIx.addressLookupTableAddresses.count, 1)
    }

    // MARK: - SanctumTypes

    func testSanctumQuoteDecoding() throws {
        let json = """
        {
            "inAmount": "2000000000",
            "outAmount": "1960000000",
            "feeAmount": "2000000",
            "feePct": "0.001"
        }
        """.data(using: .utf8)!

        let quote = try JSONDecoder().decode(SanctumQuote.self, from: json)
        XCTAssertEqual(quote.inAmount, "2000000000")
        XCTAssertEqual(quote.outAmount, "1960000000")
    }

    func testSanctumSwapResponseDecoding() throws {
        let json = """
        {"tx": "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SanctumSwapResponse.self, from: json)
        XCTAssertFalse(response.tx.isEmpty)
        XCTAssertNotNil(Data(base64Encoded: response.tx))
    }

    func testSanctumSwapRequestEncoding() throws {
        let request = SanctumSwapRequest(
            input: LSTMint.wrappedSOL,
            outputLstMint: LSTMint.jitoSOL,
            amount: "1000000000",
            quotedAmount: "980000000",
            signer: "DummyPublicKey",
            mode: "ExactIn"
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["input"] as? String, LSTMint.wrappedSOL)
        XCTAssertEqual(json?["outputLstMint"] as? String, LSTMint.jitoSOL)
        XCTAssertEqual(json?["mode"] as? String, "ExactIn")
    }

    // MARK: - HeliusTypes

    func testHeliusEnhancedTransactionWithNativeTransfers() throws {
        let json = """
        {
            "description": "Sent 1 SOL",
            "type": "TRANSFER",
            "source": "SYSTEM_PROGRAM",
            "fee": 5000,
            "feePayer": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
            "signature": "sig123",
            "slot": 100,
            "timestamp": 1700000000,
            "nativeTransfers": [
                {
                    "fromUserAccount": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
                    "toUserAccount": "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
                    "amount": 1000000000
                }
            ],
            "tokenTransfers": []
        }
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)
        XCTAssertEqual(tx.type, "TRANSFER")
        XCTAssertEqual(tx.nativeTransfers?.count, 1)
        XCTAssertEqual(tx.nativeTransfers?[0].amount, 1_000_000_000)
    }

    func testHeliusEnhancedTransactionWithTokenTransfers() throws {
        let json = """
        {
            "description": "Swapped USDC for SOL",
            "type": "SWAP",
            "source": "JUPITER",
            "fee": 5000,
            "feePayer": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
            "signature": "sig456",
            "slot": 200,
            "timestamp": 1700001000,
            "nativeTransfers": [],
            "tokenTransfers": [
                {
                    "fromUserAccount": "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
                    "toUserAccount": null,
                    "fromTokenAccount": "ATA1",
                    "toTokenAccount": "ATA2",
                    "tokenAmount": 50.5,
                    "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
                }
            ]
        }
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)
        XCTAssertEqual(tx.type, "SWAP")
        XCTAssertEqual(tx.tokenTransfers?.count, 1)
        XCTAssertNil(tx.tokenTransfers?[0].toUserAccount)
        XCTAssertEqual(tx.tokenTransfers?[0].tokenAmount, 50.5)
    }

    func testHeliusMissingOptionalFields() throws {
        let json = """
        {
            "description": "Unknown",
            "type": "UNKNOWN",
            "source": "UNKNOWN",
            "fee": 5000,
            "feePayer": "abc",
            "signature": "xyz",
            "slot": 1,
            "timestamp": 1700000000
        }
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(HeliusEnhancedTransaction.self, from: json)
        XCTAssertNil(tx.nativeTransfers)
        XCTAssertNil(tx.tokenTransfers)
    }

    // MARK: - Error Handling

    func testMalformedJSONThrows() {
        let badJSON = "not json at all".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(BalanceResult.self, from: badJSON))
    }

    func testMissingRequiredFieldThrows() {
        let json = """
        {"notTheRightField": 123}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(BalanceResult.self, from: json))
    }

    func testWrongTypeFieldThrows() {
        let json = """
        {"value": "not_a_number"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(BalanceResult.self, from: json))
    }

    func testSignatureInfoDecoding() throws {
        let json = """
        {
            "signature": "5abc123def456",
            "slot": 245000000,
            "blockTime": 1700000000,
            "err": null,
            "memo": "test memo",
            "confirmationStatus": "finalized"
        }
        """.data(using: .utf8)!

        let info = try JSONDecoder().decode(SignatureInfo.self, from: json)
        XCTAssertEqual(info.signature, "5abc123def456")
        XCTAssertEqual(info.memo, "test memo")
        XCTAssertEqual(info.confirmationStatus, "finalized")
    }

    func testSignatureInfoWithErrorDecoding() throws {
        let json = """
        {
            "signature": "errSig",
            "slot": 100,
            "blockTime": null,
            "err": "InstructionError",
            "memo": null,
            "confirmationStatus": null
        }
        """.data(using: .utf8)!

        let info = try JSONDecoder().decode(SignatureInfo.self, from: json)
        XCTAssertNotNil(info.err)
        XCTAssertNil(info.blockTime)
        XCTAssertNil(info.memo)
        XCTAssertNil(info.confirmationStatus)
    }

    // MARK: - PrioritizationFee

    func testPrioritizationFeeDecoding() throws {
        let json = """
        {"slot": 245000000, "prioritizationFee": 50000}
        """.data(using: .utf8)!

        let fee = try JSONDecoder().decode(PrioritizationFee.self, from: json)
        XCTAssertEqual(fee.slot, 245000000)
        XCTAssertEqual(fee.prioritizationFee, 50000)
    }

    // MARK: - TokenAccountBalance

    func testTokenAccountBalanceResultDecoding() throws {
        let json = """
        {
            "value": {
                "amount": "5000000",
                "decimals": 6,
                "uiAmount": 5.0,
                "uiAmountString": "5"
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(TokenAccountBalanceResult.self, from: json)
        XCTAssertEqual(result.value.amount, "5000000")
        XCTAssertEqual(result.value.decimals, 6)
        XCTAssertEqual(result.value.uiAmount, 5.0)
        XCTAssertEqual(result.value.uiAmountString, "5")
    }

    // MARK: - Batch transaction decoding

    func testBatchHeliusTransactionsDecoding() throws {
        let json = """
        [
            {
                "description": "Transfer 1",
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
                "description": "Transfer 2",
                "type": "TRANSFER",
                "source": "SYSTEM_PROGRAM",
                "fee": 5000,
                "feePayer": "sender2",
                "signature": "sig2",
                "slot": 101,
                "timestamp": 1700000100,
                "nativeTransfers": [],
                "tokenTransfers": []
            },
            {
                "description": "Swap",
                "type": "SWAP",
                "source": "JUPITER",
                "fee": 5000,
                "feePayer": "sender3",
                "signature": "sig3",
                "slot": 102,
                "timestamp": 1700000200,
                "nativeTransfers": [],
                "tokenTransfers": []
            }
        ]
        """.data(using: .utf8)!

        let txs = try JSONDecoder().decode([HeliusEnhancedTransaction].self, from: json)
        XCTAssertEqual(txs.count, 3)
        XCTAssertEqual(txs[0].type, "TRANSFER")
        XCTAssertEqual(txs[2].type, "SWAP")
    }
}
