pub mod server;
pub mod layers;
pub mod jwt;
pub mod models;
pub mod admin;

use axum::Router;
use log::info;
use tokio::net::TcpListener;
use tower_http::compression::CompressionLayer;
use tracing::level_filters::LevelFilter;
use tracing_appender::rolling::{RollingFileAppender, Rotation};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use talog_core::{file, Service};
use crate::layers::cors_layer;
use crate::server::AppState;

#[tokio::main]
async fn main() {
    init_log();

    let state = AppState::new().await;
    let router = Router::new()
        .layer(cors_layer(&state.config.origins))
        .layer(CompressionLayer::new());
    let listener = TcpListener::bind(format!("0.0.0.0:{}", state.config.port)).await.unwrap();
    axum::serve(listener, router).await.unwrap();

    let service = Service::new("data").await;
    let indices = service.get_indices();
    println!("{:#?}", indices);
    drop(service);
    file::wait_for_done();
}

fn init_log() {
    let console_layer = tracing_subscriber::fmt::layer()
        .with_ansi(true)
        .with_level(true)
        .with_target(true)
        .with_thread_ids(false)
        .with_line_number(false);

    let file_appender = RollingFileAppender::new(
        Rotation::DAILY,
        "./logs",
        "app.log",
    );
    let file_layer = tracing_subscriber::fmt::layer()
        .with_ansi(false)
        .with_writer(file_appender)
        .with_level(true)
        .with_target(true)
        .with_line_number(false);

    tracing_subscriber::registry()
        .with(console_layer)
        .with(file_layer)
        .with(LevelFilter::INFO)
        .init();

    info!("start logging...");
}