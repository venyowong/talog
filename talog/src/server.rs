use std::fs;
use std::str::FromStr;
use std::sync::Arc;
use cidr::Ipv4Cidr;
use talog_core::Service;
use crate::models::AppConfig;

#[derive(Clone)]
pub struct AppState {
    pub allowed_cidrs: Vec<Ipv4Cidr>,
    pub config: Arc<AppConfig>,
    pub service: Arc<Service>,
}

impl AppState {
    pub async fn new() -> Self {
        let config: AppConfig = serde_yaml::from_str(fs::read_to_string("config.yaml").unwrap().as_str()).unwrap();
        Self {
            allowed_cidrs: config.allowed_list.iter().map(|x| Ipv4Cidr::from_str(x).unwrap()).collect(),
            config: Arc::new(config),
            service: Arc::new(Service::new("data").await)
        }
    }
}