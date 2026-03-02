import Foundation

public enum JitoTip {
    /// Jito tip account addresses — pick one at random for each transaction
    public static let tipAccounts: [String] = [
        "96gYZGLnJYVFmbjzopPSU6QiEV5fGqZNyN9nmNhvrZU5",
        "HFqU5x63VTqvQss8hp11i4bVqkfRtQ7NmXwkiA8CBngy",
        "Cw8CFyM9FkoMi7K7Crf6HNQqf4uEMzpKw6QNghXLvLkY",
        "ADaUMid9yfUC67HyGE6d3hmtcpnxByUKTBNSNeqhPJ5X",
        "DfXygSm4jCyNCybVYYK6DwvWqjKee8pbDmJGcLWNDXjh",
        "ADuUkR4vqLUMWXxW9gh6D6L8pMSawimctcNZ5pGwDcEt",
        "DttWaMuVvTiduZRnguLF7jNxTgiMBZ1hyAumKUiL6d8u",
        "3AVi9Tg9Uo68tJfuvoKvqKNWKkC5wPdSSdeBnizKZ6jT",
    ]

    /// Maximum allowed tip: 10,000,000 lamports (0.01 SOL).
    /// Prevents misconfigured agents from tipping entire wallet balance.
    public static let maxTipLamports: UInt64 = 10_000_000

    /// Build a tip instruction (SOL transfer to a random Jito tip account).
    /// Throws if `lamports` exceeds `maxTipLamports`.
    public static func tipInstruction(from: SolanaPublicKey, lamports: UInt64) throws -> Instruction {
        guard lamports <= maxTipLamports else {
            throw SolanaError.decodingError("Jito tip \(lamports) lamports exceeds max \(maxTipLamports) lamports (0.01 SOL)")
        }
        let randomIndex = Int.random(in: 0..<tipAccounts.count)
        let tipAccount = try SolanaPublicKey(base58: tipAccounts[randomIndex])
        return SystemProgram.transfer(from: from, to: tipAccount, lamports: lamports)
    }

    /// Default tip amount: 840,000 lamports (~0.00084 SOL)
    public static let defaultTipLamports: UInt64 = 840_000
}
