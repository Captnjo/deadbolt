use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum WalletSource {
    KeypairFile { path: String },
    Keychain,
    Hardware,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletInfo {
    pub address: String,
    pub name: String,
    pub source: WalletSource,
}
