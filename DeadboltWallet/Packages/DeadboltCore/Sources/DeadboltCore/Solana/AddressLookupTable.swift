import Foundation

/// A deserialized Solana Address Lookup Table (ALT).
public struct AddressLookupTable: Sendable {
    public let key: SolanaPublicKey
    public let addresses: [SolanaPublicKey]

    public init(key: SolanaPublicKey, addresses: [SolanaPublicKey]) {
        self.key = key
        self.addresses = addresses
    }

    /// Deserialize an Address Lookup Table from on-chain account data.
    ///
    /// ALT account data layout:
    /// - Bytes 0-3: Type discriminator (4 bytes)
    /// - Bytes 4-11: Deactivation slot (8 bytes, u64 LE)
    /// - Bytes 12-19: Last extended slot (8 bytes, u64 LE)
    /// - Byte 20: Last extended start index (1 byte)
    /// - Byte 21: Padding (1 byte)
    /// - Bytes 22-23: Padding (2 bytes)
    /// - Bytes 24-55: Authority (32 bytes, all zeros if none)
    /// - Bytes 56+: Addresses (each 32 bytes)
    public static func deserialize(key: SolanaPublicKey, data: Data) throws -> AddressLookupTable {
        let headerSize = 56
        guard data.count >= headerSize else {
            throw SolanaError.decodingError("ALT data too short: \(data.count) bytes, expected at least \(headerSize)")
        }

        let addressDataLength = data.count - headerSize
        guard addressDataLength % 32 == 0 else {
            throw SolanaError.decodingError(
                "ALT address data length \(addressDataLength) is not a multiple of 32"
            )
        }

        let addressCount = addressDataLength / 32
        var addresses: [SolanaPublicKey] = []
        addresses.reserveCapacity(addressCount)

        for i in 0..<addressCount {
            let offset = headerSize + (i * 32)
            let keyData = data.subdata(in: offset..<(offset + 32))
            let pubkey = try SolanaPublicKey(data: keyData)
            addresses.append(pubkey)
        }

        return AddressLookupTable(key: key, addresses: addresses)
    }
}
