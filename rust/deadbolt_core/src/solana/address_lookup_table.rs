use crate::crypto::SolanaPublicKey;
use crate::models::DeadboltError;

/// A deserialized Solana Address Lookup Table (ALT).
#[derive(Debug, Clone)]
pub struct AddressLookupTable {
    pub key: SolanaPublicKey,
    pub addresses: Vec<SolanaPublicKey>,
}

impl AddressLookupTable {
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
    pub fn deserialize(key: SolanaPublicKey, data: &[u8]) -> Result<Self, DeadboltError> {
        let header_size = 56;
        if data.len() < header_size {
            return Err(DeadboltError::DecodingError(format!(
                "ALT data too short: {} bytes, expected at least {}",
                data.len(),
                header_size
            )));
        }

        let address_data_len = data.len() - header_size;
        if address_data_len % 32 != 0 {
            return Err(DeadboltError::DecodingError(format!(
                "ALT address data length {} is not a multiple of 32",
                address_data_len
            )));
        }

        let address_count = address_data_len / 32;
        let mut addresses = Vec::with_capacity(address_count);

        for i in 0..address_count {
            let offset = header_size + i * 32;
            let pubkey = SolanaPublicKey::from_bytes(&data[offset..offset + 32])?;
            addresses.push(pubkey);
        }

        Ok(Self { key, addresses })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_deserialize_empty() {
        let key = SolanaPublicKey::from_bytes(&[1u8; 32]).unwrap();
        let data = vec![0u8; 56]; // header only, no addresses
        let alt = AddressLookupTable::deserialize(key, &data).unwrap();
        assert!(alt.addresses.is_empty());
    }

    #[test]
    fn test_deserialize_with_addresses() {
        let key = SolanaPublicKey::from_bytes(&[1u8; 32]).unwrap();
        let mut data = vec![0u8; 56 + 64]; // header + 2 addresses
        data[56..88].copy_from_slice(&[2u8; 32]);
        data[88..120].copy_from_slice(&[3u8; 32]);
        let alt = AddressLookupTable::deserialize(key, &data).unwrap();
        assert_eq!(alt.addresses.len(), 2);
    }

    #[test]
    fn test_deserialize_too_short() {
        let key = SolanaPublicKey::from_bytes(&[1u8; 32]).unwrap();
        let data = vec![0u8; 40];
        assert!(AddressLookupTable::deserialize(key, &data).is_err());
    }
}
