use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Hash, Serialize)]
pub struct Tag {
    pub label: String,
    pub value: String,
}