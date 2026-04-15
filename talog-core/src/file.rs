use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::{BufWriter, Write};
use std::sync::mpsc::{Sender};
use std::sync::{mpsc, LockResult, Mutex, Once, OnceLock};
use std::{fs, thread};
use std::error::Error;
use std::path::Path;
use std::time::{Instant, Duration};
use once_cell::sync::Lazy;
use log::{info, warn};

pub struct FileState {
    last_write: Instant,
    writer: BufWriter<fs::File>,
}

pub enum Message {
    Append(String, String),
    Overwrite(String, String),
    Remove(String)
}

static FILES: Lazy<Mutex<HashMap<String, FileState>>> = Lazy::new(|| {Mutex::new(HashMap::new())});
static INIT: Once = Once::new();
static SENDER: OnceLock<Sender<Message>> = OnceLock::new();

fn init() {
    INIT.call_once(|| {
        let (sender, receiver) = mpsc::channel();
        SENDER.set(sender).unwrap();

        // receive logs and write into files
        thread::spawn(move || loop {
            loop {
                match receiver.recv() {
                    Ok(Message::Append(path, line)) => {
                        let p = path.clone();
                        match FILES.lock() {
                            Ok(mut files) => {
                                let state = files.entry(path).or_insert_with(|| {
                                    let file = OpenOptions::new()
                                        .create(true)
                                        .append(true)
                                        .write(true)
                                        .open(&p)
                                        .unwrap();

                                    FileState {
                                        writer: BufWriter::new(file),
                                        last_write: Instant::now(),
                                    }
                                });

                                writeln!(state.writer, "{}", line).ok();
                                state.last_write = Instant::now();
                            }
                            Err(e) => {
                                warn!("failed to lock FILES: {}", e);
                            }
                        }
                    }
                    Ok(Message::Overwrite(path, content)) => {
                        if let Err(e) = fs::write(&path, content) {
                            warn!("failed to overwrite file({}): {}", &path, e);
                        } else {
                            info!("overwrite file {}", &path);
                        }
                    }
                    Ok(Message::Remove(path)) => {
                        match FILES.lock() {
                            Ok(mut files) => {
                                files.remove(&path);
                                if let Err(e) = fs::remove_file(Path::new(&path)) {
                                    warn!("failed to remove file({}): {}", &path, e);
                                }
                            }
                            Err(e) => {
                                warn!("failed to lock FILES: {}", e);
                            }
                        }
                    }
                    Err(e) => {
                        warn!("captured a RecvError: {}", e);
                        thread::sleep(Duration::from_millis(100));
                    }
                }
            }
        });
    });

    // flush files and close temporarily unused files
    thread::spawn(|| {
        loop {
            thread::sleep(Duration::from_secs(5));

            let mut files = FILES.lock().ok();
            if let Some(files) = files.as_mut() {
                let len = files.len();
                for file in files.values_mut() {
                    if file.writer.buffer().len() > 0 {
                        if !file.writer.flush().is_ok() {
                            continue;
                        }

                        file.last_write = Instant::now();
                    }
                }

                files.retain(|_, v| {
                    let duration = Instant::now().duration_since(v.last_write);
                    duration < Duration::from_secs(30)
                });
                let new_len = files.len();
                if new_len < len {
                    info!("closed {} temporarily unused bucket files", len - new_len);
                }
            }
        }
    });
}

pub fn append_line(path: &str, line: &str) -> Result<(), Box<dyn Error>> {
    init();
    if let Some(sender) = SENDER.get() {
        sender.send(Message::Append(path.to_string(), line.to_string()))?;
        Ok(())
    } else {
        Err("failed to get sender".into())
    }
}

pub fn overwrite(path: &str, content: &str) -> Result<(), Box<dyn Error>> {
    init();
    if let Some(sender) = SENDER.get() {
        sender.send(Message::Overwrite(path.to_string(), content.to_string()))?;
        Ok(())
    } else {
        Err("failed to get sender".into())
    }
}

pub fn remove_file(path: &str) -> Result<(), Box<dyn Error>> {
    init();
    if let Some(sender) = SENDER.get() {
        sender.send(Message::Remove(path.to_string()))?;
        Ok(())
    } else {
        Err("failed to get sender".into())
    }
}