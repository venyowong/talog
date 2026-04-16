use std::fmt::{Debug, Display, Formatter};
use ::serde::{Deserialize, Serialize};
use serde::de::DeserializeOwned;
use talog_macros::TalogIndex;

pub const INDEX_MAPPING_INDEX_NAME: &str = "index_mapping";

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
pub struct FieldMapping {
    pub is_tag: bool,
    pub name: String,
    pub typ: FieldType
}

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
pub enum FieldType {
    Number,
    String
}

#[derive(Clone, Debug, Deserialize, Serialize, TalogIndex)]
#[index("index_mapping")]
pub struct IndexMapping {
    pub fields: Vec<FieldMapping>,
    pub log_regex: Option<String>,
    #[tag]
    pub log_type: LogType,
    pub mapping_time: i64,
    pub name: String
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub enum LogType {
    Raw,
    Json
}

pub trait TalogIndex : DeserializeOwned + Serialize {
    fn field_mappings() -> Vec<FieldMapping>;
    fn index_name() -> &'static str;
}

impl Display for LogType {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            LogType::Raw => {
                write!(f, "Raw")
            }
            LogType::Json => {
                write!(f, "Json")
            }
        }
    }
}

impl Display for FieldType {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        match self {
            FieldType::Number => {
                write!(f, "Number")
            }
            FieldType::String => {
                write!(f, "String")
            }
        }
    }
}