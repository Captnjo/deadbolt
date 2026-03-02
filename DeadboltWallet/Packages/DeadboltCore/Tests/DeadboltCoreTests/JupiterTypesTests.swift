import XCTest
@testable import DeadboltCore

final class JupiterTypesTests: XCTestCase {

    // MARK: - JupiterQuote Decoding

    func testJupiterQuoteDecoding() throws {
        let json = """
        {
            "inputMint": "So11111111111111111111111111111111111111112",
            "inAmount": "1000000000",
            "outputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "outAmount": "24359100",
            "otherAmountThreshold": "24237305",
            "swapMode": "ExactIn",
            "slippageBps": 50,
            "priceImpactPct": "0.001",
            "routePlan": [
                {
                    "swapInfo": {
                        "ammKey": "HcoJfuNAqBN4n3YoHPTRRsKpcdmrhuGqGPsNV3Kb6TSv",
                        "label": "Raydium",
                        "inputMint": "So11111111111111111111111111111111111111112",
                        "outputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                        "inAmount": "1000000000",
                        "outAmount": "24359100",
                        "feeAmount": "25000",
                        "feeMint": "So11111111111111111111111111111111111111112"
                    },
                    "percent": 100
                }
            ]
        }
        """.data(using: .utf8)!

        let quote = try JSONDecoder().decode(JupiterQuote.self, from: json)

        XCTAssertEqual(quote.inputMint, "So11111111111111111111111111111111111111112")
        XCTAssertEqual(quote.inAmount, "1000000000")
        XCTAssertEqual(quote.outputMint, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        XCTAssertEqual(quote.outAmount, "24359100")
        XCTAssertEqual(quote.otherAmountThreshold, "24237305")
        XCTAssertEqual(quote.swapMode, "ExactIn")
        XCTAssertEqual(quote.slippageBps, 50)
        XCTAssertEqual(quote.priceImpactPct, "0.001")
        XCTAssertEqual(quote.routePlan.count, 1)
        XCTAssertEqual(quote.routePlan[0].percent, 100)
        XCTAssertEqual(quote.routePlan[0].swapInfo.label, "Raydium")
        XCTAssertEqual(quote.routePlan[0].swapInfo.ammKey, "HcoJfuNAqBN4n3YoHPTRRsKpcdmrhuGqGPsNV3Kb6TSv")
        XCTAssertEqual(quote.routePlan[0].swapInfo.feeAmount, "25000")
    }

    func testJupiterQuoteDecodingNullPriceImpact() throws {
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

    func testJupiterQuoteRoundTrip() throws {
        let json = """
        {
            "inputMint": "So11111111111111111111111111111111111111112",
            "inAmount": "500000000",
            "outputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "outAmount": "12000000",
            "otherAmountThreshold": "11940000",
            "swapMode": "ExactIn",
            "slippageBps": 50,
            "priceImpactPct": "0.01",
            "routePlan": [
                {
                    "swapInfo": {
                        "ammKey": "TestAMMKey123",
                        "label": "Orca",
                        "inputMint": "So11111111111111111111111111111111111111112",
                        "outputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                        "inAmount": "500000000",
                        "outAmount": "12000000",
                        "feeAmount": "5000",
                        "feeMint": "So11111111111111111111111111111111111111112"
                    },
                    "percent": 100
                }
            ]
        }
        """.data(using: .utf8)!

        // Decode
        let quote = try JSONDecoder().decode(JupiterQuote.self, from: json)

        // Re-encode
        let encoded = try JSONEncoder().encode(quote)

        // Decode again and verify
        let roundTripped = try JSONDecoder().decode(JupiterQuote.self, from: encoded)
        XCTAssertEqual(roundTripped.inputMint, quote.inputMint)
        XCTAssertEqual(roundTripped.outAmount, quote.outAmount)
        XCTAssertEqual(roundTripped.routePlan.count, quote.routePlan.count)
    }

    // MARK: - JupiterSwapInstructions Decoding

    func testJupiterSwapInstructionsDecoding() throws {
        let json = """
        {
            "tokenLedgerInstruction": null,
            "computeBudgetInstructions": [
                {
                    "programId": "ComputeBudget111111111111111111111111111111",
                    "accounts": [],
                    "data": "AgDwAQ=="
                },
                {
                    "programId": "ComputeBudget111111111111111111111111111111",
                    "accounts": [],
                    "data": "AwDKmj4AAAAAAAA="
                }
            ],
            "setupInstructions": [
                {
                    "programId": "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
                    "accounts": [
                        {"pubkey": "UserWallet11111111111111111111111111111111", "isSigner": true, "isWritable": true},
                        {"pubkey": "TokenAccount1111111111111111111111111111111", "isSigner": false, "isWritable": true}
                    ],
                    "data": "AQ=="
                }
            ],
            "swapInstruction": {
                "programId": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
                "accounts": [
                    {"pubkey": "UserWallet11111111111111111111111111111111", "isSigner": true, "isWritable": true},
                    {"pubkey": "PoolAccount1111111111111111111111111111111", "isSigner": false, "isWritable": true}
                ],
                "data": "4wAABBCC"
            },
            "cleanupInstruction": null,
            "addressLookupTableAddresses": [
                "HyaB3W9q6XdA5xwpU4XnSZV94htfmbmqJXZcEbRaJutt",
                "5quBtoiQqxF9Jv6KYKctB59NT3gtJD2Y65kdnB1Uev3h"
            ]
        }
        """.data(using: .utf8)!

        let swapIx = try JSONDecoder().decode(JupiterSwapInstructions.self, from: json)

        XCTAssertNil(swapIx.tokenLedgerInstruction)
        XCTAssertEqual(swapIx.computeBudgetInstructions.count, 2)
        XCTAssertEqual(swapIx.setupInstructions.count, 1)
        XCTAssertEqual(swapIx.swapInstruction.programId, "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4")
        XCTAssertEqual(swapIx.swapInstruction.accounts.count, 2)
        XCTAssertTrue(swapIx.swapInstruction.accounts[0].isSigner)
        XCTAssertTrue(swapIx.swapInstruction.accounts[0].isWritable)
        XCTAssertFalse(swapIx.swapInstruction.accounts[1].isSigner)
        XCTAssertNil(swapIx.cleanupInstruction)
        XCTAssertEqual(swapIx.addressLookupTableAddresses.count, 2)
        XCTAssertEqual(swapIx.addressLookupTableAddresses[0], "HyaB3W9q6XdA5xwpU4XnSZV94htfmbmqJXZcEbRaJutt")
    }

    // MARK: - JupiterInstructionData Decoding

    func testJupiterInstructionDataDecoding() throws {
        let json = """
        {
            "programId": "11111111111111111111111111111111",
            "accounts": [
                {"pubkey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "isSigner": true, "isWritable": true},
                {"pubkey": "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", "isSigner": false, "isWritable": true}
            ],
            "data": "AQIDBA=="
        }
        """.data(using: .utf8)!

        let ix = try JSONDecoder().decode(JupiterInstructionData.self, from: json)

        XCTAssertEqual(ix.programId, "11111111111111111111111111111111")
        XCTAssertEqual(ix.accounts.count, 2)
        XCTAssertEqual(ix.accounts[0].pubkey, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertTrue(ix.accounts[0].isSigner)
        XCTAssertTrue(ix.accounts[0].isWritable)
        XCTAssertFalse(ix.accounts[1].isSigner)
        XCTAssertEqual(ix.data, "AQIDBA==")

        // Verify base64 data decodes correctly
        let decoded = Data(base64Encoded: ix.data)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, Data([1, 2, 3, 4]))
    }

    func testJupiterSwapInstructionsWithTokenLedger() throws {
        let json = """
        {
            "tokenLedgerInstruction": {
                "programId": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
                "accounts": [],
                "data": "AA=="
            },
            "computeBudgetInstructions": [],
            "setupInstructions": [],
            "swapInstruction": {
                "programId": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
                "accounts": [],
                "data": "AQ=="
            },
            "cleanupInstruction": {
                "programId": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
                "accounts": [],
                "data": "Ag=="
            },
            "addressLookupTableAddresses": []
        }
        """.data(using: .utf8)!

        let swapIx = try JSONDecoder().decode(JupiterSwapInstructions.self, from: json)

        XCTAssertNotNil(swapIx.tokenLedgerInstruction)
        XCTAssertNotNil(swapIx.cleanupInstruction)
        XCTAssertEqual(swapIx.computeBudgetInstructions.count, 0)
        XCTAssertEqual(swapIx.setupInstructions.count, 0)
        XCTAssertEqual(swapIx.addressLookupTableAddresses.count, 0)
    }

    func testJupiterQuoteMultiHopRoute() throws {
        let json = """
        {
            "inputMint": "So11111111111111111111111111111111111111112",
            "inAmount": "1000000000",
            "outputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "outAmount": "24500000",
            "otherAmountThreshold": "24377500",
            "swapMode": "ExactIn",
            "slippageBps": 50,
            "priceImpactPct": "0.005",
            "routePlan": [
                {
                    "swapInfo": {
                        "ammKey": "AMMKey1",
                        "label": "Raydium",
                        "inputMint": "So11111111111111111111111111111111111111112",
                        "outputMint": "IntermediateMint11111111111111111111111111",
                        "inAmount": "500000000",
                        "outAmount": "12250000",
                        "feeAmount": "10000",
                        "feeMint": "So11111111111111111111111111111111111111112"
                    },
                    "percent": 50
                },
                {
                    "swapInfo": {
                        "ammKey": "AMMKey2",
                        "label": "Orca",
                        "inputMint": "So11111111111111111111111111111111111111112",
                        "outputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                        "inAmount": "500000000",
                        "outAmount": "12250000",
                        "feeAmount": "10000",
                        "feeMint": "So11111111111111111111111111111111111111112"
                    },
                    "percent": 50
                }
            ]
        }
        """.data(using: .utf8)!

        let quote = try JSONDecoder().decode(JupiterQuote.self, from: json)
        XCTAssertEqual(quote.routePlan.count, 2)
        XCTAssertEqual(quote.routePlan[0].percent, 50)
        XCTAssertEqual(quote.routePlan[1].percent, 50)
        XCTAssertEqual(quote.routePlan[0].swapInfo.label, "Raydium")
        XCTAssertEqual(quote.routePlan[1].swapInfo.label, "Orca")
    }
}
