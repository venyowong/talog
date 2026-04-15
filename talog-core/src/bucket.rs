use std::path::PathBuf;
use md5::{Md5, Digest};
use serde::{Deserialize, Serialize};
use crate::Tag;

#[derive(Clone, Debug, Deserialize, Hash, Serialize)]
pub struct Bucket {
    pub file: String,
    pub key: String,
    pub tags: Vec<Tag>
}

impl Bucket {
    pub fn new(path: &str, tags: &[Tag]) -> Bucket {
        let mut strs: Vec<String> = tags.iter().map(|x| format!("{}:{}", x.label, x.value)).collect();
        strs.sort();
        let key = strs.join(";");
        let mut hasher = Md5::new();
        hasher.update(key.as_bytes());
        let key = hex::encode(hasher.finalize());
        let path = PathBuf::from(path);
        let file = path.join(key.clone() + ".log");
        Bucket {
            file: file.to_str().unwrap().to_string(),
            key,
            tags: tags.to_vec()
        }
    }
}

impl Eq for Bucket {}

impl PartialEq for Bucket {
    fn eq(&self, other: &Self) -> bool {
        self.key == other.key
    }
}