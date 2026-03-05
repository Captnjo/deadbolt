use sha2::{Digest, Sha256};

use crate::crypto::SolanaPublicKey;
use crate::models::DeadboltError;

/// Find a valid program-derived address by iterating bump seeds from 255 down to 0.
pub fn find_program_address(
    seeds: &[&[u8]],
    program_id: &SolanaPublicKey,
) -> Result<(SolanaPublicKey, u8), DeadboltError> {
    for bump in (0..=255u8).rev() {
        let mut seeds_with_bump: Vec<&[u8]> = seeds.to_vec();
        let bump_slice = [bump];
        seeds_with_bump.push(&bump_slice);
        if let Ok(address) = create_program_address(&seeds_with_bump, program_id) {
            return Ok((address, bump));
        }
    }
    Err(DeadboltError::PdaNotFound)
}

/// Create a program address from seeds.
/// Throws if the resulting point is on the Ed25519 curve.
pub fn create_program_address(
    seeds: &[&[u8]],
    program_id: &SolanaPublicKey,
) -> Result<SolanaPublicKey, DeadboltError> {
    for seed in seeds {
        if seed.len() > 32 {
            return Err(DeadboltError::PdaSeedTooLong(seed.len()));
        }
    }

    let mut hasher = Sha256::new();
    for seed in seeds {
        hasher.update(seed);
    }
    hasher.update(program_id.as_bytes());
    hasher.update(b"ProgramDerivedAddress");
    let hash: [u8; 32] = hasher.finalize().into();

    if is_on_curve(&hash) {
        return Err(DeadboltError::PdaOnCurve);
    }

    SolanaPublicKey::from_bytes(&hash)
}

/// Check if 32 bytes represent a valid Ed25519 curve point.
/// Uses the twisted Edwards curve equation: -x^2 + y^2 = 1 + d*x^2*y^2
fn is_on_curve(data: &[u8; 32]) -> bool {
    // p = 2^255 - 19
    const P: [u64; 4] = [
        0xFFFFFFFFFFFFFFED,
        0xFFFFFFFFFFFFFFFF,
        0xFFFFFFFFFFFFFFFF,
        0x7FFFFFFFFFFFFFFF,
    ];

    // d = -121665/121666 mod p
    const D: [u64; 4] = [
        0x75EB4DCA135978A3,
        0x00700A4D4141D8AB,
        0x8CC740797779E898,
        0x52036CEE2B6FFE73,
    ];

    // Extract y-coordinate (clear sign bit)
    let mut y_bytes = *data;
    y_bytes[31] &= 0x7F;

    let y = bytes_to_limbs(&y_bytes);

    // Check y < p
    if !less_than(&y, &P) {
        return false;
    }

    let one = [1u64, 0, 0, 0];

    // y^2 mod p
    let y2 = mod_mul(&y, &y, &P);

    // u = y^2 - 1 mod p
    let u = mod_sub(&y2, &one, &P);

    // v = d * y^2 + 1 mod p
    let v = mod_add(&mod_mul(&D, &y2, &P), &one, &P);

    // v_inv = v^(p-2) mod p
    let p_minus_2: [u64; 4] = [
        0xFFFFFFFFFFFFFFEB,
        0xFFFFFFFFFFFFFFFF,
        0xFFFFFFFFFFFFFFFF,
        0x7FFFFFFFFFFFFFFF,
    ];
    let v_inv = mod_pow(&v, &p_minus_2, &P);

    // x^2 = u * v_inv mod p
    let x2 = mod_mul(&u, &v_inv, &P);

    if is_zero(&x2) {
        return true;
    }

    // Euler criterion: x^2 is a QR iff x^2^((p-1)/2) == 1 mod p
    let p_minus_1_over_2: [u64; 4] = [
        0xFFFFFFFFFFFFFFF6,
        0xFFFFFFFFFFFFFFFF,
        0xFFFFFFFFFFFFFFFF,
        0x3FFFFFFFFFFFFFFF,
    ];
    let result = mod_pow(&x2, &p_minus_1_over_2, &P);

    is_one(&result)
}

// 256-bit arithmetic using 4 u64 limbs (little-endian)

fn bytes_to_limbs(bytes: &[u8; 32]) -> [u64; 4] {
    let mut limbs = [0u64; 4];
    for i in 0..4 {
        let mut val = 0u64;
        for j in 0..8 {
            val |= (bytes[i * 8 + j] as u64) << (j * 8);
        }
        limbs[i] = val;
    }
    limbs
}

fn is_zero(a: &[u64; 4]) -> bool {
    a[0] == 0 && a[1] == 0 && a[2] == 0 && a[3] == 0
}

fn is_one(a: &[u64; 4]) -> bool {
    a[0] == 1 && a[1] == 0 && a[2] == 0 && a[3] == 0
}

fn less_than(a: &[u64; 4], b: &[u64; 4]) -> bool {
    for i in (0..4).rev() {
        if a[i] < b[i] {
            return true;
        }
        if a[i] > b[i] {
            return false;
        }
    }
    false // equal
}

fn add_raw(a: &[u64; 4], b: &[u64; 4]) -> ([u64; 4], bool) {
    let mut result = [0u64; 4];
    let mut carry = 0u64;
    for i in 0..4 {
        let (s1, c1) = a[i].overflowing_add(b[i]);
        let (s2, c2) = s1.overflowing_add(carry);
        result[i] = s2;
        carry = (c1 as u64) + (c2 as u64);
    }
    (result, carry > 0)
}

fn sub_raw(a: &[u64; 4], b: &[u64; 4]) -> [u64; 4] {
    let mut result = [0u64; 4];
    let mut borrow = 0u64;
    for i in 0..4 {
        let (s1, c1) = a[i].overflowing_sub(b[i]);
        let (s2, c2) = s1.overflowing_sub(borrow);
        result[i] = s2;
        borrow = (c1 as u64) + (c2 as u64);
    }
    result
}

fn mod_add(a: &[u64; 4], b: &[u64; 4], p: &[u64; 4]) -> [u64; 4] {
    let (result, carry) = add_raw(a, b);
    if carry || !less_than(&result, p) {
        sub_raw(&result, p)
    } else {
        result
    }
}

fn mod_sub(a: &[u64; 4], b: &[u64; 4], p: &[u64; 4]) -> [u64; 4] {
    if less_than(a, b) {
        let (a_plus_p, _) = add_raw(a, p);
        sub_raw(&a_plus_p, b)
    } else {
        sub_raw(a, b)
    }
}

/// Multiply two u64 values and return (hi, lo) as a stable alternative to widening_mul.
#[inline]
fn mul_u64(a: u64, b: u64) -> (u64, u64) {
    let full = (a as u128) * (b as u128);
    ((full >> 64) as u64, full as u64)
}

fn mod_mul(a: &[u64; 4], b: &[u64; 4], p: &[u64; 4]) -> [u64; 4] {
    // Full 512-bit product
    let mut product = [0u64; 8];

    for i in 0..4 {
        let mut carry = 0u64;
        for j in 0..4 {
            let (hi, lo) = mul_u64(a[i], b[j]);
            let (s1, c1) = product[i + j].overflowing_add(lo);
            let (s2, c2) = s1.overflowing_add(carry);
            product[i + j] = s2;
            carry = hi.wrapping_add(c1 as u64).wrapping_add(c2 as u64);
        }
        product[i + 4] = carry;
    }

    reduce_512(&product, p)
}

fn reduce_512(product: &[u64; 8], p: &[u64; 4]) -> [u64; 4] {
    let mut result = *product;

    for _ in 0..2 {
        let mut high = [0u64; 5];
        high[0] = (result[3] >> 63) | (result[4] << 1);
        high[1] = (result[4] >> 63) | (result[5] << 1);
        high[2] = (result[5] >> 63) | (result[6] << 1);
        high[3] = (result[6] >> 63) | (result[7] << 1);
        high[4] = result[7] >> 63;

        result[3] &= 0x7FFFFFFFFFFFFFFF;
        result[4] = 0;
        result[5] = 0;
        result[6] = 0;
        result[7] = 0;

        let mut carry = 0u64;
        for i in 0..5 {
            let (hi, lo) = mul_u64(high[i], 19);
            let (s1, c1) = result[i].overflowing_add(lo);
            let (s2, c2) = s1.overflowing_add(carry);
            result[i] = s2;
            carry = hi.wrapping_add(c1 as u64).wrapping_add(c2 as u64);
        }
        for i in 5..8 {
            let (s, c) = result[i].overflowing_add(carry);
            result[i] = s;
            carry = c as u64;
            if carry == 0 {
                break;
            }
        }
    }

    let mut r = [result[0], result[1], result[2], result[3]];
    if !less_than(&r, p) {
        r = sub_raw(&r, p);
    }
    r
}

fn mod_pow(base: &[u64; 4], exp: &[u64; 4], p: &[u64; 4]) -> [u64; 4] {
    let mut result = [1u64, 0, 0, 0];
    let mut b = *base;

    for i in 0..4 {
        let mut e = exp[i];
        for _ in 0..64 {
            if e & 1 == 1 {
                result = mod_mul(&result, &b, p);
            }
            b = mod_mul(&b, &b, p);
            e >>= 1;
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_program_address_system() {
        // Test that we can find ATA for a known wallet
        let owner = SolanaPublicKey::from_bytes(&[1u8; 32]).unwrap();
        let token_program = SolanaPublicKey::from_base58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA").unwrap();
        let mint = SolanaPublicKey::from_bytes(&[2u8; 32]).unwrap();
        let ata_program = SolanaPublicKey::from_base58("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL").unwrap();

        let result = find_program_address(
            &[owner.as_bytes(), token_program.as_bytes(), mint.as_bytes()],
            &ata_program,
        );
        assert!(result.is_ok());
        let (addr, _bump) = result.unwrap();
        assert_eq!(addr.as_bytes().len(), 32);
    }

    #[test]
    fn test_seed_too_long() {
        let program = SolanaPublicKey::from_bytes(&[0u8; 32]).unwrap();
        let long_seed = vec![0u8; 33];
        let result = create_program_address(&[&long_seed], &program);
        assert!(matches!(result, Err(DeadboltError::PdaSeedTooLong(33))));
    }
}
