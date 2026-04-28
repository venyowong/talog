use axum::http::StatusCode;
use axum::Json;
use axum::response::IntoResponse;
use serde::{Deserialize, Serialize};
use talog_core::{LogType, Tag};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ApiResult<T> {
    pub code: i32,
    pub data: Option<T>,
    pub msg: Option<String>
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct AppConfig {
    pub admin_pwd: String,
    pub allowed_list: Vec<String>,
    pub jwt_secret: String,
    pub origins: Vec<String>,
    pub port: u16,
}

#[derive(Debug)]
pub struct AppError(anyhow::Error);

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct IndexLogRequest {
    pub name: String,
    pub log: String,
    pub log_type: LogType,
    pub parse_log: bool,
    #[serde(default)]
    pub tags: Vec<Tag>
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct IndexLogsRequest {
    pub name: String,
    pub log_type: LogType,
    pub logs: Vec<String>,
    pub parse_log: bool,
    #[serde(default)]
    pub tags: Vec<Tag>
}

#[derive(Clone, Deserialize, Serialize)]
pub struct JwtClaims {
    pub exp: usize,
    pub sub: String,
}

impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResult {
                code: -1,
                msg: Some(self.0.to_string()),
                data: None::<()>,
            }),
        ).into_response()
    }
}

impl From<anyhow::Error> for AppError {
    fn from(err: anyhow::Error) -> Self {
        Self(err)
    }
}