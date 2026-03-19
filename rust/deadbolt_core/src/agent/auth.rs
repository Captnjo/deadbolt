use axum::extract::Request;
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use constant_time_eq::constant_time_eq;

use std::sync::Arc;

use super::server::AppState;

/// Auth middleware: validates Bearer token against config.
pub async fn auth_middleware(
    axum::extract::State(state): axum::extract::State<Arc<AppState>>,
    request: Request,
    next: Next,
) -> Response {
    let auth_header = request
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok());

    let token = match auth_header {
        Some(h) if h.starts_with("Bearer ") => &h[7..],
        _ => {
            return (
                StatusCode::UNAUTHORIZED,
                r#"{"error":"Missing or invalid Authorization header"}"#,
            )
                .into_response();
        }
    };

    let is_valid = {
        let valid_tokens = state.api_tokens.lock().unwrap();
        let token_bytes = token.as_bytes();
        valid_tokens.iter().any(|stored| {
            constant_time_eq(stored.as_bytes(), token_bytes)
        })
    };

    if !is_valid {
        return (
            StatusCode::UNAUTHORIZED,
            r#"{"error":"Invalid API token"}"#,
        )
            .into_response();
    }

    next.run(request).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request as HttpRequest;
    use axum::middleware;
    use axum::routing::get;
    use axum::Router;
    use std::collections::HashMap;
    use std::sync::Mutex;
    use tokio::sync::broadcast;
    use tower::ServiceExt;
    use crate::models::config::GuardrailsConfig;
    use super::super::guardrails::GuardrailsEngine;

    fn make_app(tokens: Vec<String>) -> Router {
        let (tx, _rx) = broadcast::channel(16);
        let state = Arc::new(AppState {
            api_tokens: Mutex::new(tokens),
            intents: Mutex::new(HashMap::new()),
            guardrails: Mutex::new(GuardrailsEngine::new(GuardrailsConfig::default())),
            wallet_address: Mutex::new(None),
            intent_sender: tx,
            wallet_data: std::sync::RwLock::new(super::super::server::WalletDataSnapshot::default()),
        });

        Router::new()
            .route("/test", get(|| async { "ok" }))
            .route_layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            ))
            .with_state(state)
    }

    #[tokio::test]
    async fn test_valid_token_passes() {
        let app = make_app(vec!["secret-token-abc".to_string()]);
        let response = app
            .oneshot(
                HttpRequest::builder()
                    .uri("/test")
                    .header("authorization", "Bearer secret-token-abc")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        // Valid token must not be rejected with 401
        assert_ne!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn test_invalid_token_rejected() {
        let app = make_app(vec!["correct-token".to_string()]);
        let response = app
            .oneshot(
                HttpRequest::builder()
                    .uri("/test")
                    .header("authorization", "Bearer wrong-token")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn test_missing_auth_header_rejected() {
        let app = make_app(vec!["some-token".to_string()]);
        let response = app
            .oneshot(
                HttpRequest::builder()
                    .uri("/test")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[test]
    fn test_uses_constant_time_eq() {
        // Code-review test: confirm constant_time_eq is available and used in this module.
        // The `use constant_time_eq::constant_time_eq;` import at the top of the file
        // and the `constant_time_eq(stored.as_bytes(), token_bytes)` call in auth_middleware
        // satisfy INFR-06. This test exercises the function directly to prove it compiles
        // and behaves correctly.
        assert!(constant_time_eq(b"token", b"token"));
        assert!(!constant_time_eq(b"token", b"other"));
        // Different-length tokens must not match
        assert!(!constant_time_eq(b"tok", b"token"));
    }
}
