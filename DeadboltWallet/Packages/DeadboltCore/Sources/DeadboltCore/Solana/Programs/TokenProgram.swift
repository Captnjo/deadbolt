import Foundation

public enum TokenProgram {
    public static let programId = try! SolanaPublicKey(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
    public static let associatedTokenProgramId = try! SolanaPublicKey(base58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")

    /// Transfer SPL tokens from one token account to another.
    /// Instruction data: u8(3) Transfer variant + u64 amount LE (9 bytes total)
    public static func transfer(
        source: SolanaPublicKey,
        destination: SolanaPublicKey,
        owner: SolanaPublicKey,
        amount: UInt64
    ) -> Instruction {
        var data = Data(count: 9)
        data[0] = 3 // Transfer instruction variant
        var val = amount
        withUnsafeBytes(of: &val) { bytes in
            data.replaceSubrange(1..<9, with: bytes)
        }

        return Instruction(
            programId: programId,
            accounts: [
                AccountMeta(publicKey: source, isSigner: false, isWritable: true),
                AccountMeta(publicKey: destination, isSigner: false, isWritable: true),
                AccountMeta(publicKey: owner, isSigner: true, isWritable: false),
            ],
            data: data
        )
    }

    /// Create an associated token account for the given owner and mint.
    /// Uses the Associated Token Account program.
    public static func createAssociatedTokenAccount(
        payer: SolanaPublicKey,
        owner: SolanaPublicKey,
        mint: SolanaPublicKey
    ) throws -> Instruction {
        let ata = try SolanaPublicKey.associatedTokenAddress(owner: owner, mint: mint)

        return Instruction(
            programId: associatedTokenProgramId,
            accounts: [
                AccountMeta(publicKey: payer, isSigner: true, isWritable: true),
                AccountMeta(publicKey: ata, isSigner: false, isWritable: true),
                AccountMeta(publicKey: owner, isSigner: false, isWritable: false),
                AccountMeta(publicKey: mint, isSigner: false, isWritable: false),
                AccountMeta(publicKey: SystemProgram.programId, isSigner: false, isWritable: false),
                AccountMeta(publicKey: programId, isSigner: false, isWritable: false),
            ],
            data: Data()
        )
    }
}
