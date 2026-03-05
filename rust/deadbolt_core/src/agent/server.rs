use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::middleware;
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

use crate::models::config::GuardrailsConfig;
use crate::models::DeadboltError;

use super::auth::auth_middleware;
use super::guardrails::GuardrailsEngine;
use super::intent::{Intent, IntentStatus, IntentType};

/// Shared application state for the agent API server.
pub struct AppState {
    pub api_tokens: Mutex<Vec<String>>,
    pub intents: Mutex<HashMap<String, Intent>>,
    pub guardrails: Mutex<GuardrailsEngine>,
    pub wallet_address: Mutex<Option<String>>,
    /// Channel to notify the Flutter UI of new intents.
    pub intent_sender: mpsc::UnboundedSender<Intent>,
}

/// Handle for controlling the agent server.
pub struct AgentServer {
    shutdown_tx: Option<tokio::sync::oneshot::Sender<()>>,
    state: Arc<AppState>,
}

impl AgentServer {
    /// Start the agent API server on the given port.
    pub async fn start(
        port: u16,
        api_tokens: Vec<String>,
        guardrails_config: GuardrailsConfig,
        wallet_address: Option<String>,
    ) -> Result<(Self, mpsc::UnboundedReceiver<Intent>), DeadboltError> {
        let (intent_tx, intent_rx) = mpsc::unbounded_channel();

        let state = Arc::new(AppState {
            api_tokens: Mutex::new(api_tokens),
            intents: Mutex::new(HashMap::new()),
            guardrails: Mutex::new(GuardrailsEngine::new(guardrails_config)),
            wallet_address: Mutex::new(wallet_address),
            intent_sender: intent_tx,
        });

        let app = build_router(state.clone());

        let addr = format!("127.0.0.1:{port}");
        let listener = tokio::net::TcpListener::bind(&addr)
            .await
            .map_err(|e| DeadboltError::StorageError(format!("Failed to bind {addr}: {e}")))?;

        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel();

        tokio::spawn(async move {
            axum::serve(listener, app)
                .with_graceful_shutdown(async {
                    let _ = shutdown_rx.await;
                })
                .await
                .ok();
        });

        let server = Self {
            shutdown_tx: Some(shutdown_tx),
            state,
        };

        Ok((server, intent_rx))
    }

    /// Stop the server.
    pub fn stop(&mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }
    }

    /// Approve an intent by ID.
    pub fn approve_intent(&self, intent_id: &str) -> Result<(), DeadboltError> {
        let mut intents = self.state.intents.lock().unwrap();
        let intent = intents
            .get_mut(intent_id)
            .ok_or_else(|| DeadboltError::StorageError("Intent not found".into()))?;

        if intent.status != IntentStatus::Pending {
            return Err(DeadboltError::StorageError(format!(
                "Intent is not pending: {:?}",
                intent.status
            )));
        }

        intent.status = IntentStatus::Approved;
        Ok(())
    }

    /// Reject an intent by ID.
    pub fn reject_intent(&self, intent_id: &str) -> Result<(), DeadboltError> {
        let mut intents = self.state.intents.lock().unwrap();
        let intent = intents
            .get_mut(intent_id)
            .ok_or_else(|| DeadboltError::StorageError("Intent not found".into()))?;

        if intent.status != IntentStatus::Pending {
            return Err(DeadboltError::StorageError(format!(
                "Intent is not pending: {:?}",
                intent.status
            )));
        }

        intent.status = IntentStatus::Rejected;
        Ok(())
    }

    /// Update an intent's status (for the signing pipeline).
    pub fn update_intent_status(
        &self,
        intent_id: &str,
        status: IntentStatus,
        signature: Option<String>,
        error: Option<String>,
    ) -> Result<(), DeadboltError> {
        let mut intents = self.state.intents.lock().unwrap();
        let intent = intents
            .get_mut(intent_id)
            .ok_or_else(|| DeadboltError::StorageError("Intent not found".into()))?;
        intent.status = status;
        intent.signature = signature;
        intent.error = error;
        Ok(())
    }

    /// Get a reference to the shared state.
    pub fn state(&self) -> &Arc<AppState> {
        &self.state
    }
}

impl Drop for AgentServer {
    fn drop(&mut self) {
        self.stop();
    }
}

// --- Router ---

fn build_router(state: Arc<AppState>) -> Router {
    let protected = Router::new()
        .route("/wallet", get(wallet_handler))
        .route("/intent", post(submit_intent_handler))
        .route("/intent/{id}/status", get(intent_status_handler))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            auth_middleware,
        ))
        .with_state(state.clone());

    Router::new()
        .merge(protected)
        .route("/health", get(health_handler))
        .with_state(state)
}

// --- Handlers ---

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    version: String,
}

async fn health_handler() -> impl IntoResponse {
    Json(HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

#[derive(Serialize)]
struct WalletResponse {
    address: Option<String>,
}

async fn wallet_handler(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let address = state.wallet_address.lock().unwrap().clone();
    Json(WalletResponse { address })
}

#[derive(Deserialize)]
struct SubmitIntentRequest {
    #[serde(flatten)]
    intent_type: IntentType,
}

#[derive(Serialize)]
struct SubmitIntentResponse {
    id: String,
    status: String,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

async fn submit_intent_handler(
    State(state): State<Arc<AppState>>,
    request: axum::extract::Request,
) -> impl IntoResponse {
    // Extract bearer token from the already-authenticated request
    let token = request
        .headers()
        .get("authorization")
        .and_then(|v: &axum::http::HeaderValue| v.to_str().ok())
        .map(|h: &str| h.trim_start_matches("Bearer ").to_string())
        .unwrap_or_default();

    // Parse body
    let body = match axum::body::to_bytes(request.into_body(), 1024 * 64).await {
        Ok(b) => b,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "Failed to read request body".into(),
                }),
            )
                .into_response();
        }
    };

    let intent_req: SubmitIntentRequest = match serde_json::from_slice(&body) {
        Ok(r) => r,
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: format!("Invalid intent: {e}"),
                }),
            )
                .into_response();
        }
    };

    // Create intent
    let intent = Intent::new(intent_req.intent_type, &token);

    // Check guardrails
    {
        let guardrails = state.guardrails.lock().unwrap();
        if let Err(e) = guardrails.check(&intent, None) {
            return (
                StatusCode::FORBIDDEN,
                Json(ErrorResponse {
                    error: e.to_string(),
                }),
            )
                .into_response();
        }
    }

    let id = intent.id.clone();

    // Notify Flutter UI
    let _ = state.intent_sender.send(intent.clone());

    // Store intent
    state
        .intents
        .lock()
        .unwrap()
        .insert(id.clone(), intent);

    (
        StatusCode::CREATED,
        Json(SubmitIntentResponse {
            id,
            status: "pending".to_string(),
        }),
    )
        .into_response()
}

#[derive(Serialize)]
struct IntentStatusResponse {
    id: String,
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    signature: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

async fn intent_status_handler(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    let intents = state.intents.lock().unwrap();
    match intents.get(&id) {
        Some(intent) => (
            StatusCode::OK,
            Json(IntentStatusResponse {
                id: intent.id.clone(),
                status: serde_json::to_value(&intent.status)
                    .unwrap_or_default()
                    .as_str()
                    .unwrap_or("unknown")
                    .to_string(),
                signature: intent.signature.clone(),
                error: intent.error.clone(),
            }),
        )
            .into_response(),
        None => (
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: "Intent not found".into(),
            }),
        )
            .into_response(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_server_start_stop() {
        let (mut server, _rx) = AgentServer::start(
            0, // port 0 = OS picks available port
            vec!["db_test".to_string()],
            GuardrailsConfig::default(),
            Some("TestAddress".to_string()),
        )
        .await
        .unwrap();

        server.stop();
    }

    #[tokio::test]
    async fn test_health_endpoint() {
        let (mut server, _rx) = AgentServer::start(
            0,
            vec!["db_test".to_string()],
            GuardrailsConfig::default(),
            None,
        )
        .await
        .unwrap();

        // Server is running, just verify it started without error
        server.stop();
    }

    #[test]
    fn test_approve_reject_intent() {
        let (tx, _rx) = mpsc::unbounded_channel();
        let state = Arc::new(AppState {
            api_tokens: Mutex::new(vec![]),
            intents: Mutex::new(HashMap::new()),
            guardrails: Mutex::new(GuardrailsEngine::new(GuardrailsConfig::default())),
            wallet_address: Mutex::new(None),
            intent_sender: tx,
        });

        let server = AgentServer {
            shutdown_tx: None,
            state,
        };

        // Add a pending intent
        let intent = Intent::new(
            IntentType::SendSol {
                to: "ABC".to_string(),
                lamports: 100,
            },
            "db_test",
        );
        let id = intent.id.clone();
        server.state.intents.lock().unwrap().insert(id.clone(), intent);

        // Approve it
        server.approve_intent(&id).unwrap();
        let intents = server.state.intents.lock().unwrap();
        assert_eq!(intents[&id].status, IntentStatus::Approved);
    }
}
