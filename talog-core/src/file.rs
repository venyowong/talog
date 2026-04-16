use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::{BufWriter, Write};
use std::sync::mpsc::{Sender};
use std::sync::{mpsc, Arc, LockResult, Mutex, Once, OnceLock};
use std::{fs, thread};
use std::error::Error;
use std::path::Path;
use std::thread::JoinHandle;
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
static HANDLE: OnceLock<Mutex<Option<JoinHandle<()>>>> = OnceLock::new();
static INIT: Once = Once::new();
static SENDER: OnceLock<Mutex<Option<Sender<Message>>>> = OnceLock::new();

fn init() {
    INIT.call_once(|| {
        let (sender, receiver) = mpsc::channel();
        SENDER.set(Mutex::new(Some(sender))).unwrap();

        // receive logs and write into files
        let handle = thread::spawn(move || {
            for message in receiver {
                match message {
                    Message::Append(path, line) => {
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
                    Message::Overwrite(path, content) => {
                        if let Err(e) = fs::write(&path, content) {
                            warn!("failed to overwrite file({}): {}", &path, e);
                        } else {
                            info!("overwrite file {}", &path);
                        }
                    }
                    Message::Remove(path) => {
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
                }
            }
        });
        HANDLE.set(Mutex::new(Some(handle))).unwrap();
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
        let guard = sender.lock()?;
        let sender = guard.as_ref().unwrap();
        sender.send(Message::Append(path.to_string(), line.to_string()))?;
        Ok(())
    } else {
        Err("failed to get sender".into())
    }
}

pub fn wait_for_done() {
    if let Some(mutex) = SENDER.get() {
        mutex.lock().unwrap().take();
    }
    if let Some(mutex) = HANDLE.get() {
        let handle = mutex.lock()
            .unwrap()
            .take();
        if let Some(handle) = handle {
            handle.join().unwrap();
            info!("file mod stop to consume messages")
        }
    }

    let mut files = FILES.lock().ok();
    if let Some(files) = files.as_mut() {
        for file in files.values_mut() {
            if file.writer.buffer().len() > 0 {
                file.writer.flush().ok();
            }
        }
    }
    info!("files flushed");
}

pub fn overwrite(path: &str, content: &str) -> Result<(), Box<dyn Error>> {
    init();
    if let Some(sender) = SENDER.get() {
        let guard = sender.lock()?;
        let sender = guard.as_ref().unwrap();
        sender.send(Message::Overwrite(path.to_string(), content.to_string()))?;
        Ok(())
    } else {
        Err("failed to get sender".into())
    }
}

pub fn remove_file(path: &str) -> Result<(), Box<dyn Error>> {
    init();
    if let Some(sender) = SENDER.get() {
        let guard = sender.lock()?;
        let sender = guard.as_ref().unwrap();
        sender.send(Message::Remove(path.to_string()))?;
        Ok(())
    } else {
        Err("failed to get sender".into())
    }
}