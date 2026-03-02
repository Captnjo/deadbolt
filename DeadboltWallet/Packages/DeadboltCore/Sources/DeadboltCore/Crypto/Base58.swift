import Foundation

public enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    private static let decodeTable: [UInt8: UInt8] = {
        var table = [UInt8: UInt8]()
        for (i, c) in alphabet.enumerated() {
            table[c.asciiValue!] = UInt8(i)
        }
        return table
    }()

    public static func encode(_ data: Data) -> String {
        let bytes = [UInt8](data)

        // Count leading zeros
        var zeros = 0
        while zeros < bytes.count && bytes[zeros] == 0 { zeros += 1 }

        // Allocate enough space in base58 representation
        var buf = [UInt8](repeating: 0, count: bytes.count * 2)
        let size = buf.count

        for i in zeros..<bytes.count {
            var carry = Int(bytes[i])
            for j in stride(from: size - 1, through: 0, by: -1) {
                carry += 256 * Int(buf[j])
                buf[j] = UInt8(carry % 58)
                carry /= 58
            }
        }

        // Skip leading zeros in base58 result
        var it = 0
        while it < size && buf[it] == 0 { it += 1 }

        // Build output string
        var result = String(repeating: "1", count: zeros)
        while it < size {
            result.append(alphabet[Int(buf[it])])
            it += 1
        }

        return result
    }

    public static func decode(_ string: String) throws -> Data {
        let chars = Array(string.utf8)

        // Count leading '1's
        var zeros = 0
        while zeros < chars.count && chars[zeros] == UInt8(ascii: "1") { zeros += 1 }

        // Allocate enough space
        var buf = [UInt8](repeating: 0, count: chars.count)
        let size = buf.count

        for i in zeros..<chars.count {
            guard let value = decodeTable[chars[i]] else {
                throw SolanaError.invalidBase58Character(Character(UnicodeScalar(chars[i])))
            }
            var carry = Int(value)
            for j in stride(from: size - 1, through: 0, by: -1) {
                carry += 58 * Int(buf[j])
                buf[j] = UInt8(carry % 256)
                carry /= 256
            }
        }

        // Skip leading zeros in byte representation
        var it = 0
        while it < size && buf[it] == 0 { it += 1 }

        // Build output: leading zero bytes + decoded bytes
        var result = Data(repeating: 0, count: zeros)
        result.append(contentsOf: buf[it..<size])

        return result
    }
}
