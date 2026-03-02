import Foundation

/// A single Solana instruction to be included in a transaction message.
public struct Instruction: Sendable {
    public let programId: SolanaPublicKey
    public let accounts: [AccountMeta]
    public let data: Data

    public init(programId: SolanaPublicKey, accounts: [AccountMeta], data: Data) {
        self.programId = programId
        self.accounts = accounts
        self.data = data
    }
}

/// Account metadata for an instruction — specifies whether the account is a signer and/or writable.
public struct AccountMeta: Sendable, Equatable {
    public let publicKey: SolanaPublicKey
    public let isSigner: Bool
    public let isWritable: Bool

    public init(publicKey: SolanaPublicKey, isSigner: Bool, isWritable: Bool) {
        self.publicKey = publicKey
        self.isSigner = isSigner
        self.isWritable = isWritable
    }
}
