use serde::{Deserialize, Serialize};

/// Types of transaction intents an agent can submit.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum IntentType {
    SendSol {
        to: String,
        lamports: u64,
    },
    SendToken {
        to: String,
        mint: String,
        amount: u64,
    },
    Swap {
        input_mint: String,
        output_mint: String,
        amount: u64,
        slippage_bps: Option<u16>,
    },
    Stake {
        amount_lamports: u64,
        lst_mint: String,
    },
    SignMessage {
        message: String, // hex-encoded bytes
    },
}

/// Status of an intent through its lifecycle.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IntentStatus {
    Pending,
    Approved,
    Rejected,
    Signing,
    Submitted,
    Confirmed,
    Failed,
}

/// A queued intent with metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Intent {
    pub id: String,
    pub intent_type: IntentType,
    pub status: IntentStatus,
    pub api_token: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    pub created_at: u64,
}

impl Intent {
    pub fn new(intent_type: IntentType, api_token: &str) -> Self {
        let id = uuid::Uuid::new_v4().to_string();
        let created_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        Self {
            id,
            intent_type,
            status: IntentStatus::Pending,
            api_token: api_token.to_string(),
            signature: None,
            error: None,
            created_at,
        }
    }

    /// Get the SOL amount of this intent (for guardrail checks).
    pub fn sol_amount(&self) -> Option<f64> {
        match &self.intent_type {
            IntentType::SendSol { lamports, .. } => Some(*lamports as f64 / 1_000_000_000.0),
            IntentType::Stake {
                amount_lamports, ..
            } => Some(*amount_lamports as f64 / 1_000_000_000.0),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sign_message_serde_roundtrip() {
        let intent_type = IntentType::SignMessage {
            message: "48656c6c6f".to_string(),
        };
        let json = serde_json::to_string(&intent_type).unwrap();
        assert!(json.contains("\"type\":\"sign_message\""));
        assert!(json.contains("\"message\":\"48656c6c6f\""));
        let parsed: IntentType = serde_json::from_str(&json).unwrap();
        match parsed {
            IntentType::SignMessage { message } => assert_eq!(message, "48656c6c6f"),
            _ => panic!("Expected SignMessage variant"),
        }
    }

    #[test]
    fn test_all_intent_types_serde() {
        let types = vec![
            IntentType::SendSol { to: "abc".into(), lamports: 1000 },
            IntentType::SendToken { to: "abc".into(), mint: "def".into(), amount: 500 },
            IntentType::Swap { input_mint: "a".into(), output_mint: "b".into(), amount: 100, slippage_bps: Some(50) },
            IntentType::Stake { amount_lamports: 2000, lst_mint: "lst".into() },
            IntentType::SignMessage { message: "deadbeef".into() },
        ];
        for t in types {
            let json = serde_json::to_string(&t).unwrap();
            let _parsed: IntentType = serde_json::from_str(&json).unwrap();
        }
    }
}
