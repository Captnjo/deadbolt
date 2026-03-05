/// Flattened wallet info for Dart consumption.
pub struct WalletInfoDto {
    pub address: String,
    pub name: String,
    pub source: String,
}

/// Result of creating a new wallet.
pub struct CreateWalletResult {
    pub wallet: WalletInfoDto,
    pub mnemonic_words: Vec<String>,
}

/// Result of building and signing a transaction (for Dart).
pub struct SignedTxDto {
    /// Base64-encoded signed transaction, ready for RPC submission.
    pub base64: String,
    /// Transaction signature (hex-encoded).
    pub signature: String,
}

impl WalletInfoDto {
    #[flutter_rust_bridge::frb(ignore)]
    pub fn from_core(info: &deadbolt_core::WalletInfo) -> Self {
        let source = match &info.source {
            deadbolt_core::WalletSource::Keychain => "keychain".to_string(),
            deadbolt_core::WalletSource::Hardware => "hardware".to_string(),
            deadbolt_core::WalletSource::KeypairFile { path } => format!("file:{path}"),
        };
        Self {
            address: info.address.clone(),
            name: info.name.clone(),
            source,
        }
    }
}
