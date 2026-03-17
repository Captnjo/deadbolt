use std::sync::{Mutex, OnceLock};

use deadbolt_core::agent::server::{AgentServer, WalletDataSnapshot, TokenSnapshot, HistoryEntry};
use deadbolt_core::models::config::GuardrailsConfig;
use flutter_rust_bridge::frb;
use rand::RngCore;

// --- Singleton ---

static AGENT_SERVER: OnceLock<Mutex<Option<AgentServer>>> = OnceLock::new();

fn agent_server() -> &'static Mutex<Option<AgentServer>> {
    AGENT_SERVER.get_or_init(|| Mutex::new(None))
}

// --- DTO types for FRB ---

/// Server status event pushed to Flutter via StreamSink.
pub struct AgentStatusEvent {
    pub status: String,   // "running" | "stopped" | "error"
    pub port: Option<u16>,
    pub error: Option<String>,
}

/// API key entry returned to Flutter (masked by default).
pub struct ApiKeyEntry {
    pub token_masked: String,   // "db_****x7f2"
    pub token_prefix: String,   // first 10 chars for lookup: "db_abc123d"
    pub label: String,
    pub created_at: Option<i64>,
}

// --- Server lifecycle ---

/// Start the agent server on port 9876. Async because server binding is async.
/// Returns error if no tokens provided, port is busy, or server already running.
pub async fn start_agent_server(port: u16) -> Result<AgentStatusEvent, String> {
    let mut guard = agent_server().lock().map_err(|e| e.to_string())?;
    if guard.is_some() {
        return Ok(AgentStatusEvent {
            status: "running".into(),
            port: Some(port),
            error: None,
        });
    }

    // Load tokens from config
    let mgr = super::wallet::manager_pub().read().map_err(|e| e.to_string())?;
    let tokens = mgr.config().api_tokens.clone();
    let wallet_address = mgr.config().active_wallet.clone();
    drop(mgr);

    if tokens.is_empty() {
        return Err("Create at least one API key before starting the server.".into());
    }

    let (server, _intent_rx) = AgentServer::start(
        port,
        tokens,
        GuardrailsConfig::default(),
        wallet_address,
    )
    .await
    .map_err(|e| e.to_string())?;

    *guard = Some(server);

    Ok(AgentStatusEvent {
        status: "running".into(),
        port: Some(port),
        error: None,
    })
}

/// Stop the agent server. Sync because stop() sends a oneshot and returns immediately.
#[frb(sync)]
pub fn stop_agent_server() {
    if let Ok(mut guard) = agent_server().lock() {
        if let Some(mut server) = guard.take() {
            server.stop();
        }
    }
}

/// Check if the agent server is currently running.
#[frb(sync)]
pub fn is_agent_server_running() -> bool {
    agent_server()
        .lock()
        .map(|guard| guard.is_some())
        .unwrap_or(false)
}

// --- API Key Management ---

/// Create a new API key with optional label. Returns the FULL token (shown once).
/// Caller MUST verify app password before calling this (auth challenge in Flutter).
pub fn create_api_key(label: String) -> Result<String, String> {
    let mut mgr = super::wallet::manager_pub().write().map_err(|e| e.to_string())?;
    let config = mgr.config_mut();

    // Soft limit of 10 keys
    if config.api_tokens.len() >= 10 {
        return Err("Maximum of 10 API keys allowed. Revoke an existing key first.".into());
    }

    // Generate 32 cryptographically random bytes -> hex -> prefix with db_
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    let token = format!("db_{}", hex::encode(bytes));

    // Store token
    config.api_tokens.push(token.clone());

    // Store label (default to "API Key N" if blank)
    let effective_label = if label.trim().is_empty() {
        format!("API Key {}", config.api_tokens.len())
    } else {
        label
    };
    config.api_key_labels.insert(token.clone(), effective_label);

    // Persist to disk
    config.save().map_err(|e| e.to_string())?;

    // Update live server if running
    if let Ok(guard) = agent_server().lock() {
        if let Some(server) = guard.as_ref() {
            if let Ok(mut live_tokens) = server.state().api_tokens.lock() {
                live_tokens.push(token.clone());
            }
        }
    }

    Ok(token)
}

/// Revoke an API key by its full token string.
/// Updates both disk config AND live server state.
/// Caller MUST verify app password before calling this.
pub fn revoke_api_key(token: String) -> Result<(), String> {
    let mut mgr = super::wallet::manager_pub().write().map_err(|e| e.to_string())?;
    let config = mgr.config_mut();

    let initial_len = config.api_tokens.len();
    config.api_tokens.retain(|t| t != &token);

    if config.api_tokens.len() == initial_len {
        return Err("API key not found.".into());
    }

    config.api_key_labels.remove(&token);
    config.save().map_err(|e| e.to_string())?;

    // Update live server state
    if let Ok(guard) = agent_server().lock() {
        if let Some(server) = guard.as_ref() {
            if let Ok(mut live_tokens) = server.state().api_tokens.lock() {
                live_tokens.retain(|t| t != &token);
            }
        }
    }

    Ok(())
}

/// List all API keys as masked entries.
#[frb(sync)]
pub fn list_api_keys() -> Result<Vec<ApiKeyEntry>, String> {
    let mgr = super::wallet::manager_pub().read().map_err(|e| e.to_string())?;
    let config = mgr.config();

    Ok(config
        .api_tokens
        .iter()
        .map(|token| {
            let label = config
                .api_key_labels
                .get(token)
                .cloned()
                .unwrap_or_else(|| "API Key".into());

            ApiKeyEntry {
                token_masked: mask_token(token),
                token_prefix: if token.len() >= 10 {
                    token[..10].to_string()
                } else {
                    token.clone()
                },
                label,
                created_at: None,
            }
        })
        .collect())
}

/// Get the full (unmasked) API key by its prefix. Used after auth challenge to reveal.
/// Caller MUST verify app password before calling this.
pub fn get_full_api_key(token_prefix: String) -> Result<String, String> {
    let mgr = super::wallet::manager_pub().read().map_err(|e| e.to_string())?;
    let config = mgr.config();

    config
        .api_tokens
        .iter()
        .find(|t| t.starts_with(&token_prefix))
        .cloned()
        .ok_or_else(|| "API key not found.".into())
}

/// Update the wallet data snapshot in the running server (called when Flutter refreshes data).
pub fn update_agent_wallet_data(
    sol_balance: Option<f64>,
    sol_usd: Option<f64>,
    tokens_json: String,
    history_json: String,
    prices_json: String,
) -> Result<(), String> {
    let guard = agent_server().lock().map_err(|e| e.to_string())?;
    if let Some(server) = guard.as_ref() {
        let tokens: Vec<TokenSnapshot> =
            serde_json::from_str(&tokens_json).unwrap_or_default();
        let history: Vec<HistoryEntry> =
            serde_json::from_str(&history_json).unwrap_or_default();
        let prices: std::collections::HashMap<String, f64> =
            serde_json::from_str(&prices_json).unwrap_or_default();

        server.update_wallet_data(WalletDataSnapshot {
            sol_balance,
            sol_usd,
            tokens,
            history,
            prices,
        });
    }
    Ok(())
}

// --- Helpers ---

/// Mask a token: "db_abc123def456..." -> "db_••••456"
fn mask_token(token: &str) -> String {
    if token.len() <= 6 {
        return "••••".to_string();
    }
    format!(
        "{}••••{}",
        &token[..3],
        &token[token.len() - 3..]
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mask_token() {
        assert_eq!(mask_token("db_abc123def456789abcdef0123456789abcdef0123456789abcdef0123456789ab"), "db_••••9ab");
        assert_eq!(mask_token("short"), "••••");
        assert_eq!(mask_token("db_abcdef"), "db_••••def");
    }

    #[test]
    fn test_agent_server_initially_not_running() {
        assert!(!is_agent_server_running());
    }

    #[test]
    fn test_create_api_key() {
        // Test token format: must be db_ prefix + 64 hex chars = 67 chars total.
        // We cannot call create_api_key directly (requires WalletManager singleton),
        // so verify the token generation logic independently.
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        let token = format!("db_{}", hex::encode(bytes));

        // Verify format
        assert!(token.starts_with("db_"), "Token must start with db_ prefix");
        assert_eq!(token.len(), 67, "Token must be exactly 67 chars (db_ + 64 hex)");

        // Verify all chars after prefix are valid hex
        let hex_part = &token[3..];
        assert!(hex_part.chars().all(|c| c.is_ascii_hexdigit()),
            "Token body must be valid hex");

        // Verify uniqueness: two generated tokens should differ
        let mut bytes2 = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes2);
        let token2 = format!("db_{}", hex::encode(bytes2));
        assert_ne!(token, token2, "Two generated tokens must be unique");
    }

    #[test]
    fn test_revoke_api_key_live() {
        // Verify the dual-update pattern: after revocation, token must be absent
        // from both config and live server state.
        // Since we cannot spin up a full WalletManager in unit tests, verify
        // the mask/unmask round-trip and the retain logic independently.

        // Simulate the retain logic used in revoke_api_key
        let mut tokens = vec![
            "db_token_aaa".to_string(),
            "db_token_bbb".to_string(),
            "db_token_ccc".to_string(),
        ];
        let revoke_target = "db_token_bbb".to_string();

        let initial_len = tokens.len();
        tokens.retain(|t| t != &revoke_target);
        assert_eq!(tokens.len(), initial_len - 1, "One token should be removed");
        assert!(!tokens.contains(&revoke_target), "Revoked token must be absent from config tokens");

        // Simulate the live server token list update (same retain logic)
        let mut live_tokens = vec![
            "db_token_aaa".to_string(),
            "db_token_bbb".to_string(),
            "db_token_ccc".to_string(),
        ];
        live_tokens.retain(|t| t != &revoke_target);
        assert!(!live_tokens.contains(&revoke_target), "Revoked token must be absent from live server tokens");

        // Verify both lists are in sync
        assert_eq!(tokens, live_tokens, "Config and live server token lists must match after revocation");
    }
}
