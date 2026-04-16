use std::net::{Ipv4Addr, SocketAddr};
use std::str::FromStr;
use std::time::Duration;
use axum::extract::{Request, State};
use axum::http::{header, HeaderName, HeaderValue, Method, StatusCode};
use axum::middleware::Next;
use axum::response::Response;
use log::warn;
use tower_http::cors::CorsLayer;
use crate::jwt;
use crate::server::AppState;

pub async fn auth_layer(State(state): State<AppState>, request: Request, next: Next) -> Result<Response, StatusCode> {
    // is remote ip within the allowed cidrs
    let remote_addr = request.extensions().get::<SocketAddr>();
    if let Some(remote_addr) = remote_addr && let Ok(cidr) = Ipv4Addr::from_str(&remote_addr.ip().to_string()) {
        for allowed in state.allowed_cidrs {
            if allowed.contains(&cidr) {
                return Ok(next.run(request).await);
            }
        }
    }

    // is request has a valid token
    let token = request.headers().get("token");
    if let Some(token) = token {
        jwt::verify_token(&state.config.jwt_secret, token.to_str().map_err(|_| StatusCode::UNAUTHORIZED)?)
            .map_err(|e| {
                warn!("failed to verify token: {}", e);
                StatusCode::UNAUTHORIZED
            })?;
        Ok(next.run(request).await)
    } else {
        Err(StatusCode::UNAUTHORIZED)
    }
}

pub fn cors_layer(origins: &Vec<String>) -> CorsLayer {
    CorsLayer::new()
        .allow_origin(origins.iter().map(|x| x.parse::<HeaderValue>().unwrap()).collect::<Vec<_>>())
        .allow_headers([
            header::CONTENT_TYPE,
            header::AUTHORIZATION,
            HeaderName::from_static("token"),
            header::CACHE_CONTROL,
            header::EXPIRES,
            header::PRAGMA,
            header::WWW_AUTHENTICATE,
            header::ACCEPT,
            header::ACCEPT_ENCODING,
            header::ACCEPT_LANGUAGE,
            header::USER_AGENT,
            header::REFERER,
            header::ORIGIN,
            HeaderName::from_static("x-real-ip"),
            HeaderName::from_static("x-forwarded-for"),
            HeaderName::from_static("x-forwarded-proto"),
        ])
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_credentials(true)
        .max_age(Duration::from_secs(3600))
}