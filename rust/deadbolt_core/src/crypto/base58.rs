use crate::models::DeadboltError;

const ALPHABET: &[u8] = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

fn decode_table() -> [Option<u8>; 128] {
    let mut table = [None; 128];
    for (i, &c) in ALPHABET.iter().enumerate() {
        table[c as usize] = Some(i as u8);
    }
    table
}

pub fn encode(data: &[u8]) -> String {
    let mut zeros = 0;
    while zeros < data.len() && data[zeros] == 0 {
        zeros += 1;
    }

    let size = data.len() * 2;
    let mut buf = vec![0u8; size];

    for &byte in &data[zeros..] {
        let mut carry = byte as usize;
        for j in (0..size).rev() {
            carry += 256 * buf[j] as usize;
            buf[j] = (carry % 58) as u8;
            carry /= 58;
        }
    }

    let mut it = 0;
    while it < size && buf[it] == 0 {
        it += 1;
    }

    let mut result = String::with_capacity(zeros + size - it);
    for _ in 0..zeros {
        result.push('1');
    }
    while it < size {
        result.push(ALPHABET[buf[it] as usize] as char);
        it += 1;
    }

    result
}

pub fn decode(input: &str) -> Result<Vec<u8>, DeadboltError> {
    let table = decode_table();
    let chars = input.as_bytes();

    let mut zeros = 0;
    while zeros < chars.len() && chars[zeros] == b'1' {
        zeros += 1;
    }

    let size = chars.len();
    let mut buf = vec![0u8; size];

    for &c in &chars[zeros..] {
        if c >= 128 {
            return Err(DeadboltError::InvalidBase58Character(c as char));
        }
        let value = table[c as usize]
            .ok_or(DeadboltError::InvalidBase58Character(c as char))?;
        let mut carry = value as usize;
        for j in (0..size).rev() {
            carry += 58 * buf[j] as usize;
            buf[j] = (carry % 256) as u8;
            carry /= 256;
        }
    }

    let mut it = 0;
    while it < size && buf[it] == 0 {
        it += 1;
    }

    let mut result = vec![0u8; zeros];
    result.extend_from_slice(&buf[it..]);
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_decode_roundtrip() {
        let data = b"Hello, Solana!";
        let encoded = encode(data);
        let decoded = decode(&encoded).unwrap();
        assert_eq!(decoded, data);
    }

    #[test]
    fn test_leading_zeros() {
        let data = vec![0, 0, 0, 1, 2, 3];
        let encoded = encode(&data);
        assert!(encoded.starts_with("111"));
        let decoded = decode(&encoded).unwrap();
        assert_eq!(decoded, data);
    }

    #[test]
    fn test_empty() {
        let encoded = encode(&[]);
        assert_eq!(encoded, "");
        let decoded = decode("").unwrap();
        assert!(decoded.is_empty());
    }

    #[test]
    fn test_known_solana_address() {
        // System program
        let data = [0u8; 32];
        let encoded = encode(&data);
        assert_eq!(encoded, "11111111111111111111111111111111");
        let decoded = decode(&encoded).unwrap();
        assert_eq!(decoded, data);
    }

    #[test]
    fn test_invalid_character() {
        assert!(decode("invalid0OIl").is_err());
    }
}
