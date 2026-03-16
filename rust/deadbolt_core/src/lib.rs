pub mod auth;
pub mod agent;
pub mod crypto;
pub mod hardware;
pub mod models;
pub mod solana;
pub mod storage;

// Re-exports for convenience
pub use crypto::{SolanaPublicKey, SoftwareSigner, TransactionSigner};
pub use models::{DeadboltError, Result, WalletInfo, WalletSource};
