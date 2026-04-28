use std::collections::HashMap;
use anyhow::anyhow;
use axum::extract::{Query, State};
use axum::{middleware, Json, Router};
use axum::routing::{get};
use talog_core::{LogModel, LogType};
use crate::layers;
use crate::models::{ApiResult, AppError};
use crate::server::AppState;

pub async fn search_logs(State(state): State<AppState>, Query(params): Query<HashMap<String, String>>)
    -> Result<Json<ApiResult<Vec<LogModel>>>, AppError> {
    let name = params.get("name")
        .ok_or(anyhow!("missing name"))?;
    let expr = params.get("expr")
        .ok_or(anyhow!("missing expr"))?;
    let log_type = params.get("log_type")
        .ok_or(anyhow!("missing log_type"))?
        .parse::<LogType>()
        .map_err(anyhow::Error::msg)?;
    let result = state.service.search_logs(&log_type, name, expr).await;
    match result {
        Ok(result) => {
            Ok(Json(ApiResult { code: 0, msg: None, data: Some(result) }))
        }
        Err(e) => {
            Ok(Json(ApiResult { code: -1, msg: Some(format!("{:?}", e).to_string()), data: None }))
        }
    }
}

pub fn route(state: AppState) -> Router<AppState> {
    Router::new()
        .route("/logs", get(search_logs))
        .layer(middleware::from_fn_with_state(state, layers::auth_layer))
}