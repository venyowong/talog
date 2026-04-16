use std::error::Error;
use axum::extract::State;
use axum::http::StatusCode;
use axum::{Json, Router};
use axum::routing::{get, post};
use md5::{Digest, Md5};
use serde_json::Value;
use crate::jwt;
use crate::models::ApiResultWithData;
use crate::server::AppState;

pub async fn login(State(state): State<AppState>, Json(req): Json<Value>) -> Result<Json<ApiResultWithData<String>>, StatusCode> {
    let password = req.get("password")
        .ok_or(StatusCode::BAD_REQUEST)?
        .as_str()
        .ok_or(StatusCode::BAD_REQUEST)?;
    let mut hasher = Md5::new();
    hasher.update(state.config.admin_pwd.as_bytes());
    let hash = hex::encode(hasher.finalize());
    if password != hash {
        Ok(Json(ApiResultWithData {
            code: -1,
            msg: "wrong password".to_string(),
            data: "".to_string()
        }))
    } else {
        Ok(Json(ApiResultWithData {
            code: 0,
            msg: "".to_string(),
            data: jwt::generate_token(&state.config.jwt_secret)
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        }))
    }
}

pub fn route() -> Router<AppState> {
    Router::new()
        .route("/admin/login", post(login))
}