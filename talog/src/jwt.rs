use std::error::Error;
use chrono::{Duration, Utc};
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation};
use crate::models::JwtClaims;

pub fn generate_token(secret: &str) -> Result<String, Box<dyn Error>> {
    jsonwebtoken::encode(&Header::default(), &JwtClaims {
        exp: (Utc::now() + Duration::days(365 * 100)).timestamp() as usize,
        sub: "talog".to_string(),
    }, &EncodingKey::from_secret(secret.as_bytes())).map_err(|e| e.into())
}

pub fn verify_token(secret: &str, token: &str) -> Result<JwtClaims, Box<dyn Error>> {
    jsonwebtoken::decode::<JwtClaims>(token, &DecodingKey::from_secret(secret.as_bytes()), &Validation::default())
        .map(|data| data.claims)
        .map_err(|e| e.into())
}