use axum::extract::Request;
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};

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
        valid_tokens.contains(&token.to_string())
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
