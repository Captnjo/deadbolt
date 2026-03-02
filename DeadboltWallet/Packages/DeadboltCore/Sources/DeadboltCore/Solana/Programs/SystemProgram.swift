import Foundation

public enum SystemProgram {
    public static let programId = try! SolanaPublicKey(base58: "11111111111111111111111111111111")

    /// Transfer lamports from one account to another.
    /// Instruction data: u32 instruction index (2 = transfer) + u64 lamports (little-endian)
    public static func transfer(
        from: SolanaPublicKey,
        to: SolanaPublicKey,
        lamports: UInt64
    ) -> Instruction {
        var data = Data(count: 12)
        // Instruction index 2 = Transfer (little-endian u32)
        data[0] = 2
        data[1] = 0
        data[2] = 0
        data[3] = 0
        // Lamports (little-endian u64)
        var amount = lamports
        withUnsafeBytes(of: &amount) { bytes in
            data.replaceSubrange(4..<12, with: bytes)
        }

        return Instruction(
            programId: programId,
            accounts: [
                AccountMeta(publicKey: from, isSigner: true, isWritable: true),
                AccountMeta(publicKey: to, isSigner: false, isWritable: true),
            ],
            data: data
        )
    }
}
