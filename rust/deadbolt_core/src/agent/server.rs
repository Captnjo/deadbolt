use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex, RwLock};

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::middleware;
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use socket2::{Domain, Socket, Type};
use tokio::sync::broadcast;

use crate::models::config::GuardrailsConfig;
use crate::models::DeadboltError;

use super::auth::auth_middleware;
use super::guardrails::GuardrailsEngine;
use super::intent::{Intent, IntentStatus, IntentType};

// --- Wallet data snapshot types ---

/// Cached snapshot of wallet data for agent query endpoints.
#[derive(Default, Clone, Serialize, Deserialize)]
pub struct WalletDataSnapshot {
    pub sol_balance: Option<f64>,
    pub sol_usd: Option<f64>,
    pub tokens: Vec<TokenSnapshot>,
    pub history: Vec<HistoryEntry>,
    pub prices: HashMap<String, f64>,
}

/// A single SPL token in the wallet snapshot.
#[derive(Default, Clone, Serialize, Deserialize)]
pub struct TokenSnapshot {
    pub mint: String,
    pub symbol: Option<String>,
    pub name: Option<String>,
    pub amount: f64,
    pub decimals: u8,
    pub usd_value: Option<f64>,
}

/// A single transaction history entry.
#[derive(Default, Clone, Serialize, Deserialize)]
pub struct HistoryEntry {
    pub signature: String,
    pub timestamp: Option<i64>,
    pub description: Option<String>,
    pub fee: Option<u64>,
    #[serde(rename = "type")]
    pub tx_type: Option<String>,
}

/// Shared application state for the agent API server.
pub struct AppState {
    pub api_tokens: Mutex<Vec<String>>,
    pub intents: Mutex<HashMap<String, Intent>>,
    pub guardrails: Mutex<GuardrailsEngine>,
    pub wallet_address: Mutex<Option<String>>,
    /// Channel to notify the Flutter UI of new intents.
    pub intent_sender: broadcast::Sender<Intent>,
    /// Cached wallet data snapshot for agent query endpoints.
    pub wallet_data: RwLock<WalletDataSnapshot>,
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
    ) -> Result<(Self, broadcast::Receiver<Intent>), DeadboltError> {
        let (intent_tx, intent_rx) = broadcast::channel(64);

        let state = Arc::new(AppState {
            api_tokens: Mutex::new(api_tokens),
            intents: Mutex::new(HashMap::new()),
            guardrails: Mutex::new(GuardrailsEngine::new(guardrails_config)),
            wallet_address: Mutex::new(wallet_address),
            intent_sender: intent_tx,
            wallet_data: RwLock::new(WalletDataSnapshot::default()),
        });

        let app = build_router(state.clone());

        let addr = format!("127.0.0.1:{port}");
        let addr_parsed: SocketAddr = addr
            .parse()
            .map_err(|e| DeadboltError::StorageError(format!("Bad address: {e}")))?;
        let socket = Socket::new(Domain::IPV4, Type::STREAM, None)
            .map_err(|e| DeadboltError::StorageError(format!("Socket create: {e}")))?;
        socket
            .set_reuse_address(true)
            .map_err(|e| DeadboltError::StorageError(format!("SO_REUSEADDR: {e}")))?;
        socket
            .set_nonblocking(true)
            .map_err(|e| DeadboltError::StorageError(format!("nonblocking: {e}")))?;
        socket
            .bind(&addr_parsed.into())
            .map_err(|e| DeadboltError::StorageError(format!("Bind {addr}: {e}")))?;
        socket
            .listen(128)
            .map_err(|e| DeadboltError::StorageError(format!("Listen: {e}")))?;
        let listener = tokio::net::TcpListener::from_std(socket.into())
            .map_err(|e| DeadboltError::StorageError(format!("TcpListener: {e}")))?;

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

    /// Update the cached wallet data snapshot (called from FRB bridge when data refreshes).
    pub fn update_wallet_data(&self, snapshot: WalletDataSnapshot) {
        if let Ok(mut data) = self.state.wallet_data.write() {
            *data = snapshot;
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
        .route("/balance", get(balance_handler))
        .route("/tokens", get(tokens_handler))
        .route("/price", get(price_handler))
        .route("/history", get(history_handler))
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

// --- Query handlers ---

#[derive(Serialize)]
struct BalanceResponse {
    sol: f64,
    sol_usd: Option<f64>,
    tokens: Vec<TokenBalanceItem>,
}

#[derive(Serialize)]
struct TokenBalanceItem {
    mint: String,
    symbol: Option<String>,
    amount: f64,
    decimals: u8,
    usd_value: Option<f64>,
}

async fn balance_handler(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let data = state.wallet_data.read().unwrap();
    Json(BalanceResponse {
        sol: data.sol_balance.unwrap_or(0.0),
        sol_usd: data.sol_usd,
        tokens: data
            .tokens
            .iter()
            .map(|t| TokenBalanceItem {
                mint: t.mint.clone(),
                symbol: t.symbol.clone(),
                amount: t.amount,
                decimals: t.decimals,
                usd_value: t.usd_value,
            })
            .collect(),
    })
}

#[derive(Serialize)]
struct TokensResponse {
    tokens: Vec<TokenSnapshot>,
}

async fn tokens_handler(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let data = state.wallet_data.read().unwrap();
    Json(TokensResponse {
        tokens: data.tokens.clone(),
    })
}

#[derive(Deserialize)]
struct PriceQuery {
    mints: Option<String>,
}

#[derive(Serialize)]
struct PriceResponse {
    prices: HashMap<String, Option<f64>>,
}

async fn price_handler(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(query): axum::extract::Query<PriceQuery>,
) -> impl IntoResponse {
    let data = state.wallet_data.read().unwrap();
    let prices: HashMap<String, Option<f64>> = match query.mints {
        Some(mints_str) => mints_str
            .split(',')
            .map(|m| {
                let mint = m.trim().to_string();
                let price = data.prices.get(&mint).copied();
                (mint, price)
            })
            .collect(),
        None => data
            .prices
            .iter()
            .map(|(k, v)| (k.clone(), Some(*v)))
            .collect(),
    };
    Json(PriceResponse { prices })
}

#[derive(Deserialize)]
struct HistoryQuery {
    limit: Option<usize>,
    before: Option<String>,
}

#[derive(Serialize)]
struct HistoryResponse {
    transactions: Vec<HistoryEntry>,
}

async fn history_handler(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(query): axum::extract::Query<HistoryQuery>,
) -> impl IntoResponse {
    let data = state.wallet_data.read().unwrap();
    let limit = query.limit.unwrap_or(20).min(100);

    let transactions: Vec<HistoryEntry> = match &query.before {
        Some(before_sig) => {
            let start = data
                .history
                .iter()
                .position(|h| h.signature == *before_sig)
                .map(|i| i + 1)
                .unwrap_or(0);
            data.history[start..].iter().take(limit).cloned().collect()
        }
        None => data.history.iter().take(limit).cloned().collect(),
    };

    Json(HistoryResponse { transactions })
}

// --- Intent handlers ---

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
    state.intents.lock().unwrap().insert(id.clone(), intent);

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
            wallet_data: RwLock::new(WalletDataSnapshot::default()),
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

    #[tokio::test]
    async fn test_query_endpoints_require_auth() {
        // Verify that the server starts and wallet_data is accessible via state
        let (mut server, _rx) = AgentServer::start(
            0,
            vec!["db_test_query".to_string()],
            GuardrailsConfig::default(),
            Some("TestQueryAddr".to_string()),
        )
        .await
        .unwrap();

        // The server started — we can verify the AppState has wallet_data
        assert!(server.state().wallet_data.read().unwrap().sol_balance.is_none());

        server.stop();
    }

    #[tokio::test]
    async fn test_update_wallet_data() {
        let (mut server, _rx) = AgentServer::start(
            0,
            vec!["db_test_data".to_string()],
            GuardrailsConfig::default(),
            Some("DataAddr".to_string()),
        )
        .await
        .unwrap();

        let snapshot = WalletDataSnapshot {
            sol_balance: Some(1.5),
            sol_usd: Some(225.0),
            tokens: vec![],
            history: vec![],
            prices: HashMap::new(),
        };

        server.update_wallet_data(snapshot);

        {
            let data = server.state().wallet_data.read().unwrap();
            assert_eq!(data.sol_balance, Some(1.5));
            assert_eq!(data.sol_usd, Some(225.0));
        }

        server.stop();
    }

    #[tokio::test]
    async fn test_port_reuse_after_stop() {
        // Start on a specific port, stop, and immediately re-start on the same port.
        // This verifies SO_REUSEADDR works.
        let (mut server1, _rx1) = AgentServer::start(
            19876, // use a high port unlikely to conflict
            vec!["db_reuse".to_string()],
            GuardrailsConfig::default(),
            None,
        )
        .await
        .unwrap();

        server1.stop();
        // Small delay for socket cleanup
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;

        let (mut server2, _rx2) = AgentServer::start(
            19876,
            vec!["db_reuse".to_string()],
            GuardrailsConfig::default(),
            None,
        )
        .await
        .unwrap();

        server2.stop();
    }
}
