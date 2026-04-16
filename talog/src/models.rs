use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ApiResult {
    pub code: i32,
    pub msg: String
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct  ApiResultWithData<T> {
    pub code: i32,
    pub msg: String,
    pub data: T
}

#[derive(Clone, Debug, Deserialize)]
pub struct AppConfig {
    pub admin_pwd: String,
    pub allowed_list: Vec<String>,
    pub jwt_secret: String,
    pub origins: Vec<String>,
    pub port: u16,
}

#[derive(Clone, Deserialize, Serialize)]
pub struct JwtClaims {
    pub exp: usize,
    pub sub: String,
}