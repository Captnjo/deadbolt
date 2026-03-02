import Foundation

/// Zero-on-dealloc wrapper for sensitive byte data (seeds, private keys).
/// Uses `mlock` to prevent swapping and `memset_s` to prevent compiler optimization of zeroing.
public final class SecureBytes: @unchecked Sendable {
    private var storage: ContiguousArray<UInt8>
    public let count: Int

    public init(bytes: Data) {
        self.count = bytes.count
        self.storage = ContiguousArray(bytes)
        storage.withUnsafeMutableBufferPointer { buf in
            if let ptr = buf.baseAddress {
                mlock(ptr, buf.count)
            }
        }
    }

    public init(count: Int) {
        self.count = count
        self.storage = ContiguousArray(repeating: 0, count: count)
        storage.withUnsafeMutableBufferPointer { buf in
            if let ptr = buf.baseAddress {
                mlock(ptr, buf.count)
            }
        }
    }

    deinit {
        storage.withUnsafeMutableBufferPointer { buf in
            if let ptr = buf.baseAddress {
                // memset_s is guaranteed not to be optimized away
                memset_s(ptr, buf.count, 0, buf.count)
                munlock(ptr, buf.count)
            }
        }
    }

    /// Access the raw bytes. The closure receives a read-only pointer.
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try storage.withUnsafeBufferPointer { buf in
            try body(UnsafeRawBufferPointer(buf))
        }
    }

    /// Convert to Data (copies the bytes — caller should minimize lifetime of the copy).
    public var data: Data {
        Data(storage)
    }
}

// MARK: - Data zeroing extension

extension Data {
    /// Zero the contents of this Data in place.
    /// Best-effort: only works on uniquely-referenced buffers.
    public mutating func zeroOut() {
        withUnsafeMutableBytes { buf in
            if let ptr = buf.baseAddress {
                memset_s(ptr, buf.count, 0, buf.count)
            }
        }
    }
}
