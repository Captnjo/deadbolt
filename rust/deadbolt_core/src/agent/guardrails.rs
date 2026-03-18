use std::collections::HashMap;
use std::sync::Mutex;

use crate::models::config::GuardrailsConfig;
use crate::models::DeadboltError;

use super::intent::Intent;

/// Enforces guardrail rules on agent intents.
pub struct GuardrailsEngine {
    config: GuardrailsConfig,
    /// Daily transaction count per API token.
    daily_counts: Mutex<HashMap<String, u32>>,
    /// Daily USD total per API token.
    daily_usd_totals: Mutex<HashMap<String, f64>>,
    /// Last transaction timestamp per API token (for cooldown).
    last_tx_times: Mutex<HashMap<String, u64>>,
    /// Day (UTC) for which the daily counters are valid.
    current_day: Mutex<u32>,
}

impl GuardrailsEngine {
    pub fn new(config: GuardrailsConfig) -> Self {
        let current_day = current_utc_day();
        Self {
            config,
            daily_counts: Mutex::new(HashMap::new()),
            daily_usd_totals: Mutex::new(HashMap::new()),
            last_tx_times: Mutex::new(HashMap::new()),
            current_day: Mutex::new(current_day),
        }
    }

    /// Update the guardrails configuration.
    pub fn update_config(&mut self, config: GuardrailsConfig) {
        self.config = config;
    }

    /// Check an intent against all guardrail rules.
    /// Returns Ok(()) if the intent passes, or an error describing which rule was violated.
    pub fn check(&self, intent: &Intent, usd_value: Option<f64>) -> Result<(), DeadboltError> {
        self.maybe_reset_daily_counters();

        // Per-transaction SOL limit
        if self.config.max_sol_per_tx > 0.0 {
            if let Some(sol) = intent.sol_amount() {
                if sol > self.config.max_sol_per_tx {
                    return Err(DeadboltError::GuardrailViolation(format!(
                        "Transaction exceeds max SOL per tx: {sol} > {}",
                        self.config.max_sol_per_tx
                    )));
                }
            }
        }

        // Per-transaction USD limit
        if self.config.max_usd_per_tx > 0.0 {
            if let Some(usd) = usd_value {
                if usd > self.config.max_usd_per_tx {
                    return Err(DeadboltError::GuardrailViolation(format!(
                        "Transaction exceeds max USD per tx: ${usd:.2} > ${:.2}",
                        self.config.max_usd_per_tx
                    )));
                }
            }
        }

        // Daily transaction count
        if self.config.max_daily_tx_count > 0 {
            let counts = self.daily_counts.lock().unwrap();
            let count = counts.get(&intent.api_token).copied().unwrap_or(0);
            if count >= self.config.max_daily_tx_count {
                return Err(DeadboltError::GuardrailViolation(format!(
                    "Daily transaction limit reached: {count} >= {}",
                    self.config.max_daily_tx_count
                )));
            }
        }

        // Daily USD total
        if self.config.max_daily_usd_total > 0.0 {
            if let Some(usd) = usd_value {
                let totals = self.daily_usd_totals.lock().unwrap();
                let total = totals.get(&intent.api_token).copied().unwrap_or(0.0);
                if total + usd > self.config.max_daily_usd_total {
                    return Err(DeadboltError::GuardrailViolation(format!(
                        "Daily USD total would exceed limit: ${:.2} + ${usd:.2} > ${:.2}",
                        total, self.config.max_daily_usd_total
                    )));
                }
            }
        }

        // Cooldown
        if self.config.cooldown_seconds > 0 {
            let last_times = self.last_tx_times.lock().unwrap();
            if let Some(last_time) = last_times.get(&intent.api_token) {
                let now = current_timestamp();
                let elapsed = now.saturating_sub(*last_time);
                if elapsed < self.config.cooldown_seconds as u64 {
                    let remaining = self.config.cooldown_seconds as u64 - elapsed;
                    return Err(DeadboltError::GuardrailViolation(format!(
                        "Cooldown active: {remaining}s remaining"
                    )));
                }
            }
        }

        // Token whitelist
        if !self.config.token_whitelist.is_empty() {
            if let Some(mint) = intent_mint(intent) {
                if !self.config.token_whitelist.contains(&mint) {
                    return Err(DeadboltError::GuardrailViolation(format!(
                        "Token not in whitelist: {mint}"
                    )));
                }
            }
        }

        Ok(())
    }

    /// Record a completed transaction for daily tracking.
    pub fn record_transaction(&self, api_token: &str, usd_value: Option<f64>) {
        self.maybe_reset_daily_counters();

        // Increment daily count
        {
            let mut counts = self.daily_counts.lock().unwrap();
            *counts.entry(api_token.to_string()).or_insert(0) += 1;
        }

        // Add to daily USD total
        if let Some(usd) = usd_value {
            let mut totals = self.daily_usd_totals.lock().unwrap();
            *totals.entry(api_token.to_string()).or_insert(0.0) += usd;
        }

        // Update last transaction time
        {
            let mut times = self.last_tx_times.lock().unwrap();
            times.insert(api_token.to_string(), current_timestamp());
        }
    }

    /// Reset daily counters if the day has changed.
    fn maybe_reset_daily_counters(&self) {
        let today = current_utc_day();
        let mut current = self.current_day.lock().unwrap();
        if *current != today {
            *current = today;
            self.daily_counts.lock().unwrap().clear();
            self.daily_usd_totals.lock().unwrap().clear();
        }
    }
}

/// Extract a token mint from an intent (if applicable).
fn intent_mint(intent: &Intent) -> Option<String> {
    match &intent.intent_type {
        super::intent::IntentType::SendToken { mint, .. } => Some(mint.clone()),
        super::intent::IntentType::Swap { input_mint, .. } => Some(input_mint.clone()),
        super::intent::IntentType::Stake { lst_mint, .. } => Some(lst_mint.clone()),
        super::intent::IntentType::SendSol { .. } => None,
        super::intent::IntentType::SignMessage { .. } => None,
    }
}

/// Get current UTC day as days since epoch.
fn current_utc_day() -> u32 {
    (current_timestamp() / 86400) as u32
}

/// Get current Unix timestamp in seconds.
fn current_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent::intent::{Intent, IntentType};

    fn default_config() -> GuardrailsConfig {
        GuardrailsConfig::default()
    }

    fn sol_intent(lamports: u64) -> Intent {
        Intent::new(
            IntentType::SendSol {
                to: "ABC".to_string(),
                lamports,
            },
            "db_test",
        )
    }

    fn token_intent(mint: &str, amount: u64) -> Intent {
        Intent::new(
            IntentType::SendToken {
                to: "ABC".to_string(),
                mint: mint.to_string(),
                amount,
            },
            "db_test",
        )
    }

    #[test]
    fn test_no_limits_passes() {
        let engine = GuardrailsEngine::new(default_config());
        let intent = sol_intent(1_000_000_000);
        assert!(engine.check(&intent, None).is_ok());
    }

    #[test]
    fn test_max_sol_per_tx() {
        let mut config = default_config();
        config.max_sol_per_tx = 1.0;
        let engine = GuardrailsEngine::new(config);

        // 0.5 SOL — passes
        assert!(engine.check(&sol_intent(500_000_000), None).is_ok());

        // 2.0 SOL — fails
        assert!(engine.check(&sol_intent(2_000_000_000), None).is_err());

        // Exactly 1.0 SOL — passes (not strictly greater)
        assert!(engine.check(&sol_intent(1_000_000_000), None).is_ok());
    }

    #[test]
    fn test_max_usd_per_tx() {
        let mut config = default_config();
        config.max_usd_per_tx = 100.0;
        let engine = GuardrailsEngine::new(config);

        assert!(engine.check(&sol_intent(1_000_000_000), Some(50.0)).is_ok());
        assert!(engine.check(&sol_intent(1_000_000_000), Some(150.0)).is_err());
    }

    #[test]
    fn test_daily_tx_count() {
        let mut config = default_config();
        config.max_daily_tx_count = 3;
        let engine = GuardrailsEngine::new(config);

        let intent = sol_intent(100);

        // First 3 pass
        for _ in 0..3 {
            assert!(engine.check(&intent, None).is_ok());
            engine.record_transaction("db_test", None);
        }

        // 4th fails
        assert!(engine.check(&intent, None).is_err());
    }

    #[test]
    fn test_daily_usd_total() {
        let mut config = default_config();
        config.max_daily_usd_total = 200.0;
        let engine = GuardrailsEngine::new(config);

        let intent = sol_intent(100);

        // $80 — passes
        assert!(engine.check(&intent, Some(80.0)).is_ok());
        engine.record_transaction("db_test", Some(80.0));

        // $80 more — total $160, passes
        assert!(engine.check(&intent, Some(80.0)).is_ok());
        engine.record_transaction("db_test", Some(80.0));

        // $80 more — total would be $240, fails
        assert!(engine.check(&intent, Some(80.0)).is_err());
    }

    #[test]
    fn test_cooldown() {
        let mut config = default_config();
        config.cooldown_seconds = 60; // 60 second cooldown
        let engine = GuardrailsEngine::new(config);

        let intent = sol_intent(100);

        // First passes
        assert!(engine.check(&intent, None).is_ok());
        engine.record_transaction("db_test", None);

        // Immediately after — fails (within cooldown)
        assert!(engine.check(&intent, None).is_err());
    }

    #[test]
    fn test_token_whitelist() {
        let mut config = default_config();
        config.token_whitelist = vec![
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
        ];
        let engine = GuardrailsEngine::new(config);

        // USDC — passes
        let usdc_intent = token_intent("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", 100);
        assert!(engine.check(&usdc_intent, None).is_ok());

        // Unknown token — fails
        let unknown_intent = token_intent("SomeRandomMint123", 100);
        assert!(engine.check(&unknown_intent, None).is_err());

        // SOL transfer — no mint, passes (whitelist only applies to tokens)
        let sol = sol_intent(100);
        assert!(engine.check(&sol, None).is_ok());
    }

    #[test]
    fn test_separate_token_tracking() {
        let mut config = default_config();
        config.max_daily_tx_count = 2;
        let engine = GuardrailsEngine::new(config);

        let intent1 = Intent::new(
            IntentType::SendSol {
                to: "ABC".to_string(),
                lamports: 100,
            },
            "db_token_a",
        );
        let intent2 = Intent::new(
            IntentType::SendSol {
                to: "ABC".to_string(),
                lamports: 100,
            },
            "db_token_b",
        );

        // Token A: 2 transactions
        engine.record_transaction("db_token_a", None);
        engine.record_transaction("db_token_a", None);

        // Token A blocked
        assert!(engine.check(&intent1, None).is_err());

        // Token B still has quota
        assert!(engine.check(&intent2, None).is_ok());
    }
}
