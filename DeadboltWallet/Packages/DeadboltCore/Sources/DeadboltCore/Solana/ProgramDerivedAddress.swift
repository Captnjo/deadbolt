import Foundation
import CryptoKit

extension SolanaPublicKey {
    /// Find a valid program-derived address (PDA) by iterating bump seeds from 255 down to 0.
    /// A valid PDA must NOT be on the Ed25519 curve.
    public static func findProgramAddress(
        seeds: [Data],
        programId: SolanaPublicKey
    ) throws -> (address: SolanaPublicKey, bump: UInt8) {
        for bump in stride(from: UInt8(255), through: 0, by: -1) {
            if let address = try? createProgramAddress(seeds: seeds + [Data([bump])], programId: programId) {
                return (address, bump)
            }
        }
        throw SolanaError.pdaNotFound
    }

    /// Create a program address from seeds. Throws if the resulting point is on the Ed25519 curve.
    public static func createProgramAddress(
        seeds: [Data],
        programId: SolanaPublicKey
    ) throws -> SolanaPublicKey {
        for seed in seeds {
            guard seed.count <= 32 else {
                throw SolanaError.pdaSeedTooLong(seed.count)
            }
        }

        // SHA256(seed1 + seed2 + ... + programId + "ProgramDerivedAddress")
        var hasher = SHA256()
        for seed in seeds {
            hasher.update(data: seed)
        }
        hasher.update(data: programId.data)
        hasher.update(data: Data("ProgramDerivedAddress".utf8))
        let hash = Data(hasher.finalize())

        // Reject if the hash is a valid Ed25519 public key (on-curve)
        if Ed25519CurveCheck.isOnCurve(hash) {
            throw SolanaError.pdaOnCurve
        }

        return try SolanaPublicKey(data: hash)
    }

    /// Derive the associated token address for a given owner and mint.
    public static func associatedTokenAddress(
        owner: SolanaPublicKey,
        mint: SolanaPublicKey
    ) throws -> SolanaPublicKey {
        let (address, _) = try findProgramAddress(
            seeds: [
                owner.data,
                TokenProgram.programId.data,
                mint.data,
            ],
            programId: TokenProgram.associatedTokenProgramId
        )
        return address
    }
}

// MARK: - Ed25519 on-curve check

/// Checks whether 32 bytes represent a valid Ed25519 curve point.
/// Ed25519 uses the twisted Edwards curve: -x^2 + y^2 = 1 + d*x^2*y^2
/// where d = -121665/121666 mod p, p = 2^255 - 19.
///
/// The 32 bytes encode a compressed point: little-endian y-coordinate with
/// the sign bit of x in the top bit of the last byte.
/// A point is "on curve" if the corresponding x^2 is a quadratic residue mod p.
enum Ed25519CurveCheck {
    // p = 2^255 - 19, represented as 4 UInt64 limbs (little-endian)
    // p = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED
    private static let p: [UInt64] = [
        0xFFFFFFFFFFFFFFED,
        0xFFFFFFFFFFFFFFFF,
        0xFFFFFFFFFFFFFFFF,
        0x7FFFFFFFFFFFFFFF,
    ]

    // d = -121665/121666 mod p
    // d = 37095705934669439343138083508754565189542113879843219016388785533085940283555
    // In hex: 52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3
    private static let d: [UInt64] = [
        0x75EB4DCA135978A3,
        0x00700A4D4141D8AB,
        0x8CC740797779E898,
        0x52036CEE2B6FFE73,
    ]

    static func isOnCurve(_ data: Data) -> Bool {
        guard data.count == 32 else { return false }

        // Extract y-coordinate (clear sign bit)
        var yBytes = [UInt8](data)
        yBytes[31] &= 0x7F

        let y = bytesToLimbs(yBytes)

        // Check y < p
        if !lessThan(y, p) { return false }

        // Compute y^2 mod p
        let y2 = modMul(y, y)

        // Compute u = y^2 - 1 mod p
        let u = modSub(y2, one())

        // Compute v = d * y^2 + 1 mod p
        let v = modAdd(modMul(d, y2), one())

        // Compute v_inv = v^(p-2) mod p (Fermat's little theorem)
        let vInv = modPow(v, pMinus2())

        // Compute x^2 = u * v_inv mod p
        let x2 = modMul(u, vInv)

        // Check if x^2 is zero (valid) or a quadratic residue
        if isZero(x2) { return true }

        // Euler criterion: x^2 is a QR iff x^2^((p-1)/2) == 1 mod p
        let exp = pMinus1Over2()
        let result = modPow(x2, exp)

        return isOne(result)
    }

    // MARK: - 256-bit arithmetic using 4 UInt64 limbs (little-endian)

    private static func one() -> [UInt64] { [1, 0, 0, 0] }

    private static func isZero(_ a: [UInt64]) -> Bool {
        a[0] == 0 && a[1] == 0 && a[2] == 0 && a[3] == 0
    }

    private static func isOne(_ a: [UInt64]) -> Bool {
        a[0] == 1 && a[1] == 0 && a[2] == 0 && a[3] == 0
    }

    private static func bytesToLimbs(_ bytes: [UInt8]) -> [UInt64] {
        // bytes are little-endian (32 bytes -> 4 UInt64 limbs, little-endian)
        var limbs: [UInt64] = [0, 0, 0, 0]
        for i in 0..<4 {
            var val: UInt64 = 0
            for j in 0..<8 {
                let idx = i * 8 + j
                if idx < bytes.count {
                    val |= UInt64(bytes[idx]) << (j * 8)
                }
            }
            limbs[i] = val
        }
        return limbs
    }

    private static func lessThan(_ a: [UInt64], _ b: [UInt64]) -> Bool {
        for i in stride(from: 3, through: 0, by: -1) {
            if a[i] < b[i] { return true }
            if a[i] > b[i] { return false }
        }
        return false // equal
    }

    // p - 2
    private static func pMinus2() -> [UInt64] {
        [
            0xFFFFFFFFFFFFFFEB,
            0xFFFFFFFFFFFFFFFF,
            0xFFFFFFFFFFFFFFFF,
            0x7FFFFFFFFFFFFFFF,
        ]
    }

    // (p - 1) / 2
    private static func pMinus1Over2() -> [UInt64] {
        [
            0xFFFFFFFFFFFFFFF6,
            0xFFFFFFFFFFFFFFFF,
            0xFFFFFFFFFFFFFFFF,
            0x3FFFFFFFFFFFFFFF,
        ]
    }

    // a + b mod p
    private static func modAdd(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        var result: [UInt64] = [0, 0, 0, 0]
        var carry: UInt64 = 0
        for i in 0..<4 {
            let (s1, c1) = a[i].addingReportingOverflow(b[i])
            let (s2, c2) = s1.addingReportingOverflow(carry)
            result[i] = s2
            carry = (c1 ? 1 : 0) + (c2 ? 1 : 0)
        }
        // If result >= p, subtract p
        if carry > 0 || !lessThan(result, p) {
            result = sub(result, p)
        }
        return result
    }

    // a - b mod p
    private static func modSub(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        if lessThan(a, b) {
            // a - b + p
            let aplusP = add(a, p)
            return sub(aplusP, b)
        }
        return sub(a, b)
    }

    // Raw add (no mod reduction), may overflow into carry but we handle it in modAdd
    private static func add(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        var result: [UInt64] = [0, 0, 0, 0]
        var carry: UInt64 = 0
        for i in 0..<4 {
            let (s1, c1) = a[i].addingReportingOverflow(b[i])
            let (s2, c2) = s1.addingReportingOverflow(carry)
            result[i] = s2
            carry = (c1 ? 1 : 0) + (c2 ? 1 : 0)
        }
        return result
    }

    // Raw subtract (assumes a >= b)
    private static func sub(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        var result: [UInt64] = [0, 0, 0, 0]
        var borrow: UInt64 = 0
        for i in 0..<4 {
            let (s1, c1) = a[i].subtractingReportingOverflow(b[i])
            let (s2, c2) = s1.subtractingReportingOverflow(borrow)
            result[i] = s2
            borrow = (c1 ? 1 : 0) + (c2 ? 1 : 0)
        }
        return result
    }

    // a * b mod p using schoolbook multiplication with reduction
    private static func modMul(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        // Full 512-bit product in 8 limbs
        var product: [UInt64] = [0, 0, 0, 0, 0, 0, 0, 0]

        for i in 0..<4 {
            var carry: UInt64 = 0
            for j in 0..<4 {
                let (hi, lo) = a[i].multipliedFullWidth(by: b[j])
                let (s1, c1) = product[i + j].addingReportingOverflow(lo)
                let (s2, c2) = s1.addingReportingOverflow(carry)
                product[i + j] = s2
                carry = hi &+ (c1 ? 1 : 0) &+ (c2 ? 1 : 0)
            }
            product[i + 4] = carry
        }

        // Reduce mod p using Barrett-like reduction
        // Since p = 2^255 - 19, we can use the relation: 2^255 ≡ 19 (mod p)
        return reduce512(product)
    }

    // Reduce a 512-bit number mod p = 2^255 - 19
    // Using the identity: for n = low_255_bits + high_bits * 2^255,
    // n ≡ low_255_bits + high_bits * 19 (mod p)
    private static func reduce512(_ product: [UInt64]) -> [UInt64] {
        // Split at bit 255: low = product[0..3] with top bit of [3] cleared
        // high = remaining bits shifted right by 255
        var result = product

        // We'll iteratively reduce
        for _ in 0..<2 {
            // Extract bits >= 255
            // result[3] bit 63 is bit 255, result[4..7] are higher bits
            var high: [UInt64] = [0, 0, 0, 0, 0]
            high[0] = (result[3] >> 63) | (result[4] << 1)
            high[1] = (result[4] >> 63) | (result[5] << 1)
            high[2] = (result[5] >> 63) | (result[6] << 1)
            high[3] = (result[6] >> 63) | (result[7] << 1)
            high[4] = result[7] >> 63

            // Clear high bits from result
            result[3] &= 0x7FFFFFFFFFFFFFFF
            result[4] = 0
            result[5] = 0
            result[6] = 0
            result[7] = 0

            // Add high * 19 to result
            var carry: UInt64 = 0
            for i in 0..<5 {
                let (hi, lo) = high[i].multipliedFullWidth(by: 19)
                let (s1, c1) = result[i].addingReportingOverflow(lo)
                let (s2, c2) = s1.addingReportingOverflow(carry)
                result[i] = s2
                carry = hi &+ (c1 ? 1 : 0) &+ (c2 ? 1 : 0)
            }
            // Propagate remaining carry
            for i in 5..<8 {
                let (s, c) = result[i].addingReportingOverflow(carry)
                result[i] = s
                carry = c ? 1 : 0
                if carry == 0 { break }
            }
        }

        var r: [UInt64] = [result[0], result[1], result[2], result[3]]

        // Final reduction: if r >= p, subtract p
        if !lessThan(r, p) {
            r = sub(r, p)
        }

        return r
    }

    // Modular exponentiation: base^exp mod p using square-and-multiply
    private static func modPow(_ base: [UInt64], _ exp: [UInt64]) -> [UInt64] {
        var result = one()
        var b = base

        for i in 0..<4 {
            var e = exp[i]
            for _ in 0..<64 {
                if e & 1 == 1 {
                    result = modMul(result, b)
                }
                b = modMul(b, b)
                e >>= 1
            }
        }

        return result
    }
}
