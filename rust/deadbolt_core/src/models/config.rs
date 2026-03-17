use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use super::wallet::WalletInfo;
use crate::models::DeadboltError;

/// Application configuration, persisted to ~/.deadbolt/config.json.
/// Format compatible with the existing Swift app.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppConfig {
    /// All registered wallets.
    #[serde(default)]
    pub wallets: Vec<WalletInfo>,

    /// Address of the currently active wallet.
    #[serde(default)]
    pub active_wallet: Option<String>,

    /// Network: "mainnet" or "devnet".
    #[serde(default = "default_network")]
    pub network: String,

    /// Agent API bearer tokens.
    #[serde(default)]
    pub api_tokens: Vec<String>,

    /// Labels for API keys: maps token string to user-defined label.
    /// Stored separately from api_tokens for backwards compatibility.
    #[serde(default)]
    pub api_key_labels: HashMap<String, String>,

    /// Guardrails settings.
    #[serde(default)]
    pub guardrails: GuardrailsConfig,

    /// Whether the user has completed the onboarding wizard.
    #[serde(default)]
    pub onboarding_completed: bool,

    /// Helius API key for RPC access.
    #[serde(default)]
    pub helius_api_key: String,
}

fn default_network() -> String {
    "mainnet".to_string()
}

/// Guardrails configuration for the agent API.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GuardrailsConfig {
    /// Max SOL per transaction (0 = unlimited).
    #[serde(default)]
    pub max_sol_per_tx: f64,

    /// Max USD per transaction (0 = unlimited).
    #[serde(default)]
    pub max_usd_per_tx: f64,

    /// Max daily transaction count (0 = unlimited).
    #[serde(default)]
    pub max_daily_tx_count: u32,

    /// Max daily USD total (0 = unlimited).
    #[serde(default)]
    pub max_daily_usd_total: f64,

    /// Cooldown between transactions in seconds (0 = none).
    #[serde(default)]
    pub cooldown_seconds: u32,

    /// Allowed token mints (empty = all allowed).
    #[serde(default)]
    pub token_whitelist: Vec<String>,

    /// Allowed program IDs (empty = default set).
    #[serde(default)]
    pub program_whitelist: Vec<String>,
}

impl Default for GuardrailsConfig {
    fn default() -> Self {
        Self {
            max_sol_per_tx: 0.0,
            max_usd_per_tx: 0.0,
            max_daily_tx_count: 0,
            max_daily_usd_total: 0.0,
            cooldown_seconds: 0,
            token_whitelist: Vec::new(),
            program_whitelist: Vec::new(),
        }
    }
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            wallets: Vec::new(),
            active_wallet: None,
            network: default_network(),
            api_tokens: Vec::new(),
            api_key_labels: HashMap::new(),
            guardrails: GuardrailsConfig::default(),
            onboarding_completed: false,
            helius_api_key: String::new(),
        }
    }
}

impl AppConfig {
    /// Load config from disk, or return default if file doesn't exist.
    pub fn load() -> Result<Self, DeadboltError> {
        let path = Self::config_path();
        if !path.exists() {
            return Ok(Self::default());
        }
        let data = std::fs::read_to_string(&path)
            .map_err(|e| DeadboltError::StorageError(format!("Failed to read config: {e}")))?;
        serde_json::from_str(&data)
            .map_err(|e| DeadboltError::StorageError(format!("Failed to parse config: {e}")))
    }

    /// Save config to disk.
    pub fn save(&self) -> Result<(), DeadboltError> {
        let path = Self::config_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| DeadboltError::StorageError(format!("Failed to create dir: {e}")))?;
        }
        let data = serde_json::to_string_pretty(self)
            .map_err(|e| DeadboltError::StorageError(format!("Failed to serialize config: {e}")))?;
        std::fs::write(&path, &data)
            .map_err(|e| DeadboltError::StorageError(format!("Failed to write config: {e}")))?;

        // Restrict config file permissions to owner-only (contains API tokens)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let perms = std::fs::Permissions::from_mode(0o600);
            std::fs::set_permissions(&path, perms)
                .map_err(|e| DeadboltError::StorageError(format!("chmod failed: {e}")))?;
        }

        Ok(())
    }

    /// Get the config file path: ~/.deadbolt/config.json
    pub fn config_path() -> PathBuf {
        Self::base_dir().join("config.json")
    }

    /// Get the vault directory: ~/.deadbolt/vault/
    pub fn vault_dir() -> PathBuf {
        Self::base_dir().join("vault")
    }

    /// Whether the user should be shown the onboarding wizard.
    pub fn needs_onboarding(&self) -> bool {
        !self.onboarding_completed && self.wallets.is_empty()
    }

    /// Mark onboarding as completed and persist to disk.
    pub fn mark_onboarding_completed(&mut self) -> Result<(), DeadboltError> {
        self.onboarding_completed = true;
        self.save()
    }

    /// Get the base directory: ~/.deadbolt/
    pub fn base_dir() -> PathBuf {
        let home = std::env::var("HOME")
            .or_else(|_| std::env::var("USERPROFILE"))
            .unwrap_or_else(|_| ".".to_string());
        PathBuf::from(home).join(".deadbolt")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::wallet::WalletSource;

    #[test]
    fn test_default_config() {
        let config = AppConfig::default();
        assert_eq!(config.wallets.len(), 0);
        assert_eq!(config.network, "mainnet");
        assert!(config.active_wallet.is_none());
    }

    #[test]
    fn test_config_roundtrip_json() {
        let mut config = AppConfig::default();
        config.wallets.push(WalletInfo {
            address: "ABC123".to_string(),
            name: "Test Wallet".to_string(),
            source: WalletSource::Keychain,
        });
        config.active_wallet = Some("ABC123".to_string());
        config.network = "devnet".to_string();
        config.api_tokens.push("db_abc123".to_string());
        config.guardrails.max_sol_per_tx = 10.0;

        let json = serde_json::to_string_pretty(&config).unwrap();
        let parsed: AppConfig = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed.wallets.len(), 1);
        assert_eq!(parsed.wallets[0].address, "ABC123");
        assert_eq!(parsed.active_wallet, Some("ABC123".to_string()));
        assert_eq!(parsed.network, "devnet");
        assert_eq!(parsed.api_tokens.len(), 1);
        assert_eq!(parsed.guardrails.max_sol_per_tx, 10.0);
    }

    #[test]
    fn test_config_camel_case_serde() {
        let json = r#"{
            "wallets": [],
            "activeWallet": "XYZ",
            "network": "mainnet",
            "apiTokens": ["db_test"],
            "guardrails": {
                "maxSolPerTx": 5.0,
                "maxUsdPerTx": 100.0,
                "maxDailyTxCount": 50,
                "maxDailyUsdTotal": 1000.0,
                "cooldownSeconds": 30,
                "tokenWhitelist": [],
                "programWhitelist": []
            }
        }"#;

        let config: AppConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.active_wallet, Some("XYZ".to_string()));
        assert_eq!(config.guardrails.max_sol_per_tx, 5.0);
        assert_eq!(config.guardrails.cooldown_seconds, 30);
    }

    #[test]
    fn test_config_missing_fields_use_defaults() {
        let json = r#"{}"#;
        let config: AppConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.network, "mainnet");
        assert!(config.wallets.is_empty());
    }

    #[test]
    fn test_onboarding_completed_backwards_compat() {
        // Old config files without onboardingCompleted should default to false
        let json = r#"{"wallets":[],"network":"mainnet"}"#;
        let config: AppConfig = serde_json::from_str(json).unwrap();
        assert!(!config.onboarding_completed);
        assert!(config.needs_onboarding());
    }

    #[test]
    fn test_needs_onboarding_logic() {
        let mut config = AppConfig::default();
        // Fresh install: no wallets, not completed → needs onboarding
        assert!(config.needs_onboarding());

        // User completed onboarding → no longer needs it
        config.onboarding_completed = true;
        assert!(!config.needs_onboarding());

        // User has wallets but didn't complete onboarding → no longer needs it
        config.onboarding_completed = false;
        config.wallets.push(WalletInfo {
            address: "ABC".to_string(),
            name: "Test".to_string(),
            source: WalletSource::Keychain,
        });
        assert!(!config.needs_onboarding());
    }

    #[test]
    fn test_helius_api_key_backwards_compat() {
        // Old config files without heliusApiKey should default to empty string
        let json = r#"{"wallets":[],"network":"mainnet"}"#;
        let config: AppConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.helius_api_key, "");
    }

    #[test]
    fn test_helius_api_key_roundtrip() {
        let mut config = AppConfig::default();
        config.helius_api_key = "test_key_123".to_string();
        let json = serde_json::to_string(&config).unwrap();
        assert!(json.contains("heliusApiKey"));
        let parsed: AppConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.helius_api_key, "test_key_123");
    }

    #[test]
    fn test_onboarding_completed_serde_roundtrip() {
        let mut config = AppConfig::default();
        config.onboarding_completed = true;
        let json = serde_json::to_string(&config).unwrap();
        assert!(json.contains("onboardingCompleted"));
        let parsed: AppConfig = serde_json::from_str(&json).unwrap();
        assert!(parsed.onboarding_completed);
    }

    #[test]
    fn test_api_key_labels_backwards_compat() {
        // Old config files without apiKeyLabels should default to empty HashMap
        let json = r#"{"wallets":[],"network":"mainnet","apiTokens":["db_abc"]}"#;
        let config: AppConfig = serde_json::from_str(json).unwrap();
        assert!(config.api_key_labels.is_empty());
        assert_eq!(config.api_tokens.len(), 1);
    }

    #[test]
    fn test_api_key_labels_roundtrip() {
        let mut config = AppConfig::default();
        config.api_tokens.push("db_test123".to_string());
        config
            .api_key_labels
            .insert("db_test123".to_string(), "Claude agent".to_string());
        let json = serde_json::to_string(&config).unwrap();
        assert!(json.contains("apiKeyLabels"));
        let parsed: AppConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(
            parsed.api_key_labels.get("db_test123").unwrap(),
            "Claude agent"
        );
    }
}
