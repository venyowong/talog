use std::collections::HashMap;
use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::{middleware, Json, Router};
use axum::routing::{get, post};
use chrono::Utc;
use tracing::warn;
use talog_core::IndexMapping;
use crate::{layers, models};
use crate::models::{ApiResult, IndexLogRequest, IndexLogsRequest};
use crate::server::AppState;

pub async fn get_mappings(State(state): State<AppState>) -> Result<Json<ApiResult<Vec<IndexMapping>>>, StatusCode> {
    let mappings = state.service.get_mappings(&None).await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let indices = state.service.get_indices()
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
    let mappings: Vec<IndexMapping> = mappings.into_iter()
        .filter(|x| indices.contains(&x.name))
        .collect();
    Ok(Json(ApiResult { code: 0, msg: None, data: Some(mappings) }))
}

pub async fn get_tag_values(State(state): State<AppState>, Query(params): Query<HashMap<String, String>>)
    -> Result<Json<ApiResult<Vec<String>>>, StatusCode>{
    let name = params.get("name")
        .ok_or(StatusCode::BAD_REQUEST)?;
    let label = params.get("label")
        .ok_or(StatusCode::BAD_REQUEST)?;
    let values = state.service.get_tag_values(name, label).await
        .ok_or(StatusCode::BAD_REQUEST)?;
    Ok(Json(ApiResult { code: 0, msg: None, data: Some(values) }))
}

pub async fn index_log(State(state): State<AppState>, Json(request): Json<IndexLogRequest>)
    -> Result<Json<ApiResult<()>>, StatusCode> {
    let result = state.service.index_log(&request.log_type, &request.name,
                                         &request.tags, request.parse_log, &request.log).await;
    models::convert_result(result)
}

/// index log one by one, and all logs must store in the same index
pub async fn index_log_seq(State(state): State<AppState>, Json(requests): Json<Vec<IndexLogRequest>>)
    -> Result<Json<ApiResult<()>>, StatusCode> {
    if requests.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let log_type = &requests[0].log_type;
    let index_name = &requests[0].name;
    let mapping = state.service.get_mapping(log_type, index_name).await;
    match mapping {
        None => {
            Ok(Json(ApiResult {
                code: -1,
                msg: Some(format!("{index_name} has no mapping data, please save mapping first").to_string()),
                data: None
            }))
        }
        Some(mapping) => {
            let mut count = 0;
            for request in &requests {
                if let Err(e) = state.service.index_log_with_mapping(&mapping, &request.tags, request.parse_log, &request.log) {
                    warn!("partial log({request:?}) index exception in index_log_seq")
                } else {
                    count += 1;
                }
            }
            if count > 0 {
                Ok(Json(ApiResult {
                    code: 0,
                    msg: Some(format!("success to index logs: {count}/{}", requests.len()).to_string()),
                    data: None
                }))
            } else {
                Ok(Json(ApiResult { code: -1, msg: Some("failed to index all logs".to_string()), data: None }))
            }
        }
    }
}

pub async fn index_logs(State(state): State<AppState>, Json(request): Json<IndexLogsRequest>) -> Result<Json<ApiResult<()>>, StatusCode> {
    let result = state.service.index_logs(&request.log_type, &request.name,
                                         &request.tags, request.parse_log, &request.logs).await;
    models::convert_result(result)
}

pub async fn mapping(State(state): State<AppState>, Json(mut mapping): Json<IndexMapping>) -> Result<Json<ApiResult<()>>, StatusCode> {
    let result = state.service.has_mapping_changed(&mapping).await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    if !result {
        return Ok(Json(ApiResult { code: 0, msg: Some("mapping has no change".to_string()), data: None }));
    }

    mapping.mapping_time = Utc::now().timestamp();
    let result = state.service.index(&mapping);
    models::convert_result(result)
}

pub async fn remove(State(state): State<AppState>, Query(params): Query<HashMap<String, String>>) -> Result<Json<ApiResult<()>>, StatusCode> {
    let name = params.get("name")
        .ok_or(StatusCode::BAD_REQUEST)?;
    let result = state.service.remove_index(name);
    models::convert_result(result)
}

pub fn route(state: AppState) -> Router<AppState> {
    Router::new()
        .route("/log", post(index_log))
        .route("/log/seq", post(index_log_seq))
        .route("/logs", post(index_logs))
        .route("/mapping", post(mapping))
        .route("/mappings", get(get_mappings))
        .route("/remove", post(remove))
        .route("/tag/values", get(get_tag_values))
        .layer(middleware::from_fn_with_state(state, layers::auth_layer))
}