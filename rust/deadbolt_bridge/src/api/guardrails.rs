use flutter_rust_bridge::frb;

/// DTO for passing guardrails config between Rust and Flutter.
/// Only includes fields relevant to v1 UI (enabled + token_whitelist).
pub struct GuardrailsConfigDto {
    pub enabled: bool,
    pub token_whitelist: Vec<String>,
}

/// Get current guardrails config as a DTO.
/// Reads from the WalletManager singleton config.
#[frb(sync)]
pub fn get_guardrails_config() -> GuardrailsConfigDto {
    let mgr = super::wallet::manager_pub().read().unwrap();
    let cfg = &mgr.config().guardrails;
    GuardrailsConfigDto {
        enabled: cfg.enabled,
        token_whitelist: cfg.token_whitelist.clone(),
    }
}

/// Update guardrails config. Persists to disk via AppConfig.save() and pushes to live server.
/// Called from Flutter when user changes master toggle or token whitelist.
pub fn update_guardrails_config(dto: GuardrailsConfigDto) -> Result<(), String> {
    // 1. Persist to disk config
    {
        let mut mgr = super::wallet::manager_pub().write().map_err(|e| e.to_string())?;
        let config = mgr.config_mut();
        config.guardrails.enabled = dto.enabled;
        config.guardrails.token_whitelist = dto.token_whitelist.clone();
        config.save().map_err(|e| e.to_string())?;
    }

    // 2. Push to live server if running
    if let Ok(guard) = super::agent::agent_server().lock() {
        if let Some(server) = guard.as_ref() {
            let mut engine = server.state().guardrails.lock().unwrap();
            // Read back the just-saved config to reconstruct a full GuardrailsConfig
            let full_config = {
                let mgr = super::wallet::manager_pub().read().unwrap();
                mgr.config().guardrails.clone()
            };
            engine.update_config(full_config);
        }
    }

    Ok(())
}

/// Check a manual transaction (send or swap) against guardrails.
/// Called from Flutter review screen before signing.
/// mint: the SPL token mint for send_token (None for SOL sends).
/// output_mint: the swap output token mint (None for non-swap transactions).
/// Returns None if the transaction passes, Some(violation_message) if blocked.
#[frb(sync)]
pub fn check_manual_transaction(
    mint: Option<String>,
    output_mint: Option<String>,
) -> Option<String> {
    let mgr = match super::wallet::manager_pub().read() {
        Ok(m) => m,
        Err(_) => return None, // fail-open if lock poisoned
    };
    let cfg = &mgr.config().guardrails;
    if !cfg.enabled {
        return None;
    }

    // Build a temporary engine for the check
    let engine = deadbolt_core::agent::guardrails::GuardrailsEngine::new(cfg.clone());

    // Check the primary mint (for send_token)
    if let Some(ref m) = mint {
        if let Err(e) = engine.check_token_whitelist(m) {
            return Some(e.to_string());
        }
    }

    // Check the output mint (for swap -- what you're acquiring)
    if let Some(ref om) = output_mint {
        if let Err(e) = engine.check_token_whitelist(om) {
            return Some(e.to_string());
        }
    }

    None
}
