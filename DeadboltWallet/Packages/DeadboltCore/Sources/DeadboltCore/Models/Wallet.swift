import Foundation

public enum WalletSource: Sendable, Equatable {
    case keypairFile(path: String)
    case keychain
    case hardware
}

public struct Wallet: Sendable, Identifiable {
    public let publicKey: SolanaPublicKey
    public let name: String
    public let source: WalletSource

    public var id: String { publicKey.base58 }
    public var address: String { publicKey.base58 }
    public var shortAddress: String { publicKey.shortAddress }

    public init(publicKey: SolanaPublicKey, name: String, source: WalletSource) {
        self.publicKey = publicKey
        self.name = name
        self.source = source
    }
}
