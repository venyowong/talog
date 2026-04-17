use std::error::Error;
use axum::http::StatusCode;
use axum::Json;
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

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IndexLogRequest {
    pub name: String,
    pub log: String,
    pub log_type: LogType,
    pub parse_log: bool,
    pub tags: Vec<Tag>
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct IndexLogsRequest {
    pub name: String,
    pub log_type: LogType,
    pub logs: Vec<String>,
    pub parse_log: bool,
    pub tags: Vec<Tag>
}

#[derive(Clone, Deserialize, Serialize)]
pub struct JwtClaims {
    pub exp: usize,
    pub sub: String,
}

pub fn convert_result(result: Result<(), Box<dyn Error>>) -> Result<Json<ApiResult<()>>, StatusCode> {
    match result {
        Ok(_) => { Ok(Json(ApiResult { code: 0, msg: None, data: Some(()) })) } 
        Err(e) => { Ok(Json(ApiResult { code: -1, msg: Some(format!("{:?}", e)), data: None })) }
    }
}