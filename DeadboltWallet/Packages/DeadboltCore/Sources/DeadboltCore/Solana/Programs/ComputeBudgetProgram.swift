import Foundation

public enum ComputeBudgetProgram {
    public static let programId = try! SolanaPublicKey(base58: "ComputeBudget111111111111111111111111111111")

    /// Set the compute unit limit for the transaction.
    /// Instruction data: u8 instruction type (2) + u32 units (little-endian)
    public static func setComputeUnitLimit(_ units: UInt32) -> Instruction {
        var data = Data(count: 5)
        data[0] = 2 // SetComputeUnitLimit instruction
        var val = units
        withUnsafeBytes(of: &val) { bytes in
            data.replaceSubrange(1..<5, with: bytes)
        }

        return Instruction(
            programId: programId,
            accounts: [],
            data: data
        )
    }

    /// Set the compute unit price (priority fee) in micro-lamports per compute unit.
    /// Instruction data: u8 instruction type (3) + u64 microLamports (little-endian)
    public static func setComputeUnitPrice(_ microLamports: UInt64) -> Instruction {
        var data = Data(count: 9)
        data[0] = 3 // SetComputeUnitPrice instruction
        var val = microLamports
        withUnsafeBytes(of: &val) { bytes in
            data.replaceSubrange(1..<9, with: bytes)
        }

        return Instruction(
            programId: programId,
            accounts: [],
            data: data
        )
    }
}
