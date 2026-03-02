import Foundation

public struct SolanaPublicKey: Equatable, Hashable, Sendable {
    public let data: Data

    public init(data: Data) throws {
        guard data.count == 32 else {
            throw SolanaError.invalidPublicKeyLength(data.count)
        }
        self.data = data
    }

    public init(base58: String) throws {
        let decoded = try Base58.decode(base58)
        guard decoded.count == 32 else {
            throw SolanaError.invalidPublicKeyLength(decoded.count)
        }
        self.data = decoded
    }

    public var base58: String {
        Base58.encode(data)
    }

    /// Short form for display: "ABC...XYZ"
    public var shortAddress: String {
        let full = base58
        guard full.count > 8 else { return full }
        let start = full.prefix(4)
        let end = full.suffix(4)
        return "\(start)...\(end)"
    }
}

extension SolanaPublicKey: CustomStringConvertible {
    public var description: String { base58 }
}

extension SolanaPublicKey: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        try self.init(base58: string)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(base58)
    }
}
