import Foundation

/// Solana compact-u16 encoding used for array lengths and account indices in transaction wire format.
/// Values 0–127 encode as 1 byte, 128–16383 as 2 bytes, 16384–65535 as 3 bytes.
public enum CompactU16 {

    /// Encode a UInt16 value into compact-u16 bytes
    public static func encode(_ value: UInt16) -> [UInt8] {
        var val = Int(value)
        var bytes: [UInt8] = []

        while true {
            var elem = UInt8(val & 0x7F)
            val >>= 7
            if val > 0 {
                elem |= 0x80
            }
            bytes.append(elem)
            if val == 0 {
                break
            }
        }

        return bytes
    }

    /// Decode a compact-u16 value from a byte buffer at the given offset.
    /// Returns the decoded value and the number of bytes consumed.
    public static func decode(_ data: Data, offset: Int) throws -> (value: UInt16, bytesRead: Int) {
        var val: Int = 0
        var shift: Int = 0
        var bytesRead = 0

        while bytesRead < 3 {
            guard offset + bytesRead < data.count else {
                throw SolanaError.decodingError("Unexpected end of data in compact-u16")
            }
            let byte = data[offset + bytesRead]
            val |= Int(byte & 0x7F) << shift
            bytesRead += 1

            if byte & 0x80 == 0 {
                break
            }
            shift += 7
        }

        guard val <= UInt16.max else {
            throw SolanaError.decodingError("compact-u16 value overflow: \(val)")
        }

        return (UInt16(val), bytesRead)
    }
}
