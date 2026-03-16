use thiserror::Error;

#[derive(Debug, Error)]
pub enum DeadboltError {
    #[error("Invalid Base58 character: '{0}'")]
    InvalidBase58Character(char),

    #[error("Invalid public key length: expected 32 bytes, got {0}")]
    InvalidPublicKeyLength(usize),

    #[error("Invalid keypair length: expected 64 bytes, got {0}")]
    InvalidKeypairLength(usize),

    #[error("Derived public key does not match keypair")]
    PublicKeyMismatch,

    #[error("Keypair file not found: {0}")]
    KeypairFileNotFound(String),

    #[error("Failed to parse keypair: {0}")]
    KeypairParseError(String),

    #[error("Secure storage error: {0}")]
    StorageError(String),

    #[error("Secure storage item not found")]
    StorageItemNotFound,

    #[error("RPC error {code}: {message}")]
    RpcError { code: i64, message: String },

    #[error("HTTP error: {0}")]
    HttpError(u16),

    #[error("Decoding error: {0}")]
    DecodingError(String),

    #[error("No wallet loaded")]
    NoWalletLoaded,

    #[error("Price unavailable for {0}")]
    PriceUnavailable(String),

    #[error("Could not find a valid program-derived address")]
    PdaNotFound,

    #[error("Derived address is on the Ed25519 curve (not a valid PDA)")]
    PdaOnCurve,

    #[error("PDA seed too long: {0} bytes (max 32)")]
    PdaSeedTooLong(usize),

    #[error("Token account not found: {0}")]
    TokenAccountNotFound(String),

    #[error("Vanity address: max attempts reached")]
    VanityMaxAttemptsReached,

    #[error("Invalid mnemonic: {0}")]
    InvalidMnemonic(String),

    #[error("Invalid address book entry: {0}")]
    InvalidAddressBookEntry(String),

    #[error("Authentication failed: {0}")]
    AuthenticationFailed(String),

    #[error("Signing error: {0}")]
    SigningError(String),

    #[error("Vault error: {0}")]
    VaultError(String),

    #[error("Guardrail violation: {0}")]
    GuardrailViolation(String),

    #[error("Wallet is locked")]
    WalletLocked,
}

pub type Result<T> = std::result::Result<T, DeadboltError>;
