use crate::models::DeadboltError;

/// Encode a u16 value into Solana compact-u16 bytes.
pub fn encode(value: u16) -> Vec<u8> {
    let mut val = value as usize;
    let mut bytes = Vec::with_capacity(3);

    loop {
        let mut elem = (val & 0x7F) as u8;
        val >>= 7;
        if val > 0 {
            elem |= 0x80;
        }
        bytes.push(elem);
        if val == 0 {
            break;
        }
    }

    bytes
}

/// Decode a compact-u16 value from a byte buffer at the given offset.
/// Returns (value, bytes_consumed).
pub fn decode(data: &[u8], offset: usize) -> Result<(u16, usize), DeadboltError> {
    let mut val: usize = 0;
    let mut shift: usize = 0;
    let mut bytes_read: usize = 0;

    while bytes_read < 3 {
        if offset + bytes_read >= data.len() {
            return Err(DeadboltError::DecodingError(
                "Unexpected end of data in compact-u16".into(),
            ));
        }
        let byte = data[offset + bytes_read];
        val |= ((byte & 0x7F) as usize) << shift;
        bytes_read += 1;

        if byte & 0x80 == 0 {
            break;
        }
        shift += 7;
    }

    if val > u16::MAX as usize {
        return Err(DeadboltError::DecodingError(format!(
            "compact-u16 value overflow: {val}"
        )));
    }

    Ok((val as u16, bytes_read))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_small() {
        assert_eq!(encode(0), vec![0]);
        assert_eq!(encode(1), vec![1]);
        assert_eq!(encode(127), vec![127]);
    }

    #[test]
    fn test_encode_medium() {
        assert_eq!(encode(128), vec![0x80, 0x01]);
        assert_eq!(encode(16383), vec![0xFF, 0x7F]);
    }

    #[test]
    fn test_encode_large() {
        assert_eq!(encode(16384), vec![0x80, 0x80, 0x01]);
    }

    #[test]
    fn test_roundtrip() {
        for val in [0, 1, 127, 128, 255, 1000, 16383, 16384, 65535] {
            let encoded = encode(val);
            let (decoded, bytes_read) = decode(&encoded, 0).unwrap();
            assert_eq!(decoded, val);
            assert_eq!(bytes_read, encoded.len());
        }
    }

    #[test]
    fn test_decode_with_offset() {
        let mut data = vec![0xFF, 0xFF]; // padding
        data.extend_from_slice(&encode(42));
        let (val, _) = decode(&data, 2).unwrap();
        assert_eq!(val, 42);
    }
}
