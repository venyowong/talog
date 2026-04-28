use anyhow::anyhow;
use axum::extract::State;
use axum::{Json, Router};
use axum::routing::{post};
use md5::{Digest, Md5};
use serde_json::Value;
use crate::jwt;
use crate::models::{ApiResult, AppError};
use crate::server::AppState;

pub async fn login(State(state): State<AppState>, Json(req): Json<Value>) -> Result<Json<ApiResult<String>>, AppError> {
    let password = req.get("password")
        .ok_or(anyhow!("missing password"))?
        .as_str()
        .ok_or(anyhow!("invalid password"))?;
    let mut hasher = Md5::new();
    hasher.update(state.config.admin_pwd.as_bytes());
    let hash = hex::encode(hasher.finalize());
    if password != hash {
        Ok(Json(ApiResult {
            code: -1,
            msg: Some("wrong password".to_string()),
            data: None
        }))
    } else {
        Ok(Json(ApiResult {
            code: 0,
            msg: None,
            data: Some(jwt::generate_token(&state.config.jwt_secret)?)
        }))
    }
}

pub fn route() -> Router<AppState> {
    Router::new()
        .route("/admin/login", post(login))
}