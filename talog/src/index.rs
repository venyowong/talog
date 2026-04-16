use axum::extract::State;
use axum::Json;
use crate::models::IndexLogRequest;
use crate::server::AppState;

pub async fn index_log(State(state): State<AppState>, Json(req): Json<IndexLogRequest>) -> Result<Json<()>, String> {

}