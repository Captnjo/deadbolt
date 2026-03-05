use std::fmt;

use serde::{Deserialize, Serialize};

use super::base58;
use crate::models::DeadboltError;

#[derive(Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct SolanaPublicKey {
    bytes: [u8; 32],
}

impl SolanaPublicKey {
    pub fn from_bytes(data: &[u8]) -> Result<Self, DeadboltError> {
        if data.len() != 32 {
            return Err(DeadboltError::InvalidPublicKeyLength(data.len()));
        }
        let mut bytes = [0u8; 32];
        bytes.copy_from_slice(data);
        Ok(Self { bytes })
    }

    pub fn from_base58(s: &str) -> Result<Self, DeadboltError> {
        let decoded = base58::decode(s)?;
        Self::from_bytes(&decoded)
    }

    pub fn to_base58(&self) -> String {
        base58::encode(&self.bytes)
    }

    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.bytes
    }

    pub fn short_address(&self) -> String {
        let full = self.to_base58();
        if full.len() > 8 {
            format!("{}...{}", &full[..4], &full[full.len() - 4..])
        } else {
            full
        }
    }
}

impl fmt::Debug for SolanaPublicKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "SolanaPublicKey({})", self.to_base58())
    }
}

impl fmt::Display for SolanaPublicKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_base58())
    }
}

impl Serialize for SolanaPublicKey {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.to_base58())
    }
}

impl<'de> Deserialize<'de> for SolanaPublicKey {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        Self::from_base58(&s).map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_from_base58_roundtrip() {
        let addr = "11111111111111111111111111111111";
        let key = SolanaPublicKey::from_base58(addr).unwrap();
        assert_eq!(key.to_base58(), addr);
        assert_eq!(key.as_bytes(), &[0u8; 32]);
    }

    #[test]
    fn test_invalid_length() {
        assert!(SolanaPublicKey::from_bytes(&[0u8; 31]).is_err());
        assert!(SolanaPublicKey::from_bytes(&[0u8; 33]).is_err());
    }

    #[test]
    fn test_short_address() {
        let key = SolanaPublicKey::from_base58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA").unwrap();
        let short = key.short_address();
        assert!(short.starts_with("Toke"));
        assert!(short.ends_with("Q5DA"));
        assert!(short.contains("..."));
    }
}
