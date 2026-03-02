import Foundation

/// Converts Jupiter API instruction data into native Solana `Instruction` objects.
public enum InstructionDecoder {

    /// Well-known program IDs that are safe in Jupiter swap transactions.
    public static let trustedProgramIds: Set<String> = [
        // System & Core
        "11111111111111111111111111111111",                     // System Program
        "ComputeBudget111111111111111111111111111111",          // Compute Budget
        "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",        // Token Program
        "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",        // Token-2022
        "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",       // Associated Token Account
        // Jupiter
        "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",        // Jupiter v6
        "JUP4Fb2cqiRUcaTHdrPC8h2gNsA2ETXiPDD33WcGuJB",        // Jupiter v4
        "JUP2jxvXaqu7NQY1GmNF4m1vodw12LVXYxbGL2VB",            // Jupiter v3
        "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc",        // Orca Whirlpool
        "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP",       // Orca v2
        "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8",       // Raydium AMM v4
        "CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK",       // Raydium CLMM
        "LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo",        // Meteora DLMM
        "Eo7WjKq67rjJQSZxS6z3YkapzY3eMj6Xy8X5EQVn5UaB",       // Meteora Pools
        "srmqPvymJeFKQ4zGQed1GFppgkRHL9kaELCbyksJtPX",         // Serum DEX v3
        "opnb2LAfJYbRMAHHvqjCwQxanZn7ReEHp1k81EQMQvR",         // OpenBook v2
        "MERLuDFBMmsHnsBPZw2sDQZHvXFMwp8EdjudcU2HKky",         // Mercurial
        "PhoeNiXZ8ByJGLkxNfZRnkUfjvmuYqLR89jjFHGqdXY",         // Phoenix
        "SSwpkEEcbUqx4vtoEByFjSkhKdCT862DNVb52nZg1UZ",         // Sanctum SPL Stake Pool
        "5ocnV1qiCgaQR8Jb8xWnVbApfaygJ8tNoZfgPwsgx9b",        // Sanctum Infinity
        "LSTxxxnJzKDFSLr4dUkPcmCf5VyryEqzPLz5j4bpxFp",        // Sanctum LST
        // Jito Tip
        "T1pyyaTNZsKv2WcRAB8oVnk93mLJw2XzjtVYqCsaHqt",        // Jito Tip
        "HQ2UUt18uJqKaQFJhgV9zaTdQxUZjNrsKFgoEDquBkcx",       // Jito Tip Router
    ]

    /// Decode a single Jupiter instruction into a native `Instruction`.
    /// - Parameters:
    ///   - jupiterInstruction: The instruction data from Jupiter API
    ///   - validateProgram: If true, reject unrecognized program IDs
    /// - Returns: A native `Instruction` ready for inclusion in a transaction message
    public static func decode(_ jupiterInstruction: JupiterInstructionData, validateProgram: Bool = true) throws -> Instruction {
        let programId = try SolanaPublicKey(base58: jupiterInstruction.programId)

        // Verify program ID is in the trusted set
        if validateProgram && !trustedProgramIds.contains(jupiterInstruction.programId) {
            throw SolanaError.decodingError("Untrusted program ID in Jupiter instruction: \(jupiterInstruction.programId)")
        }

        let accounts = try jupiterInstruction.accounts.map { acct in
            AccountMeta(
                publicKey: try SolanaPublicKey(base58: acct.pubkey),
                isSigner: acct.isSigner,
                isWritable: acct.isWritable
            )
        }

        guard let data = Data(base64Encoded: jupiterInstruction.data) else {
            throw SolanaError.decodingError("Invalid base64 instruction data")
        }

        return Instruction(programId: programId, accounts: accounts, data: data)
    }

    /// Decode an array of Jupiter instructions into native `Instruction` objects.
    /// - Parameters:
    ///   - instructions: The instruction data array from Jupiter API
    ///   - validateProgram: If true, reject unrecognized program IDs
    /// - Returns: Array of native `Instruction` objects
    public static func decodeAll(_ instructions: [JupiterInstructionData], validateProgram: Bool = true) throws -> [Instruction] {
        try instructions.map { try decode($0, validateProgram: validateProgram) }
    }
}
