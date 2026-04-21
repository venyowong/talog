pub mod server;
pub mod layers;
pub mod jwt;
pub mod models;
pub mod admin;
pub mod index;
pub mod search;

use std::net::SocketAddr;
use std::path::Path;
use axum::{middleware, routing, Router, ServiceExt};
use log::info;
use tokio::net::TcpListener;
use tower_http::compression::CompressionLayer;
use tower_http::services::ServeDir;
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
    let port = state.config.port.clone();
    let router = Router::new()
        .merge(admin::route())
        .nest("/index", index::route(state.clone()))
        .nest("/search", search::route(state.clone()))
        .fallback_service(routing::get_service(
            ServeDir::new(Path::new("./public"))
                .append_index_html_on_directories(true)
        ))
        .layer(cors_layer(&state.config.origins))
        .layer(CompressionLayer::new())
        .with_state(state);
    let address = format!("0.0.0.0:{}", port);
    info!("starting server on {}", &address);
    let listener = TcpListener::bind(address).await.unwrap();
    axum::serve(listener, router.into_make_service_with_connect_info::<SocketAddr>()).await.unwrap();

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