use std::collections::HashMap;
use std::error::Error;
use std::fs;
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};
use chrono::Utc;
use itertools::EitherOrBoth::{Both, Left, Right};
use itertools::Itertools;
use log::{debug, warn};
use regex::{Regex};
use serde_json::{json, Value};
use crate::{FieldMapping, Index, IndexMapping, LogType, Tag, TalogIndex, INDEX_MAPPING_INDEX_NAME};

pub struct LogModel {
    pub data: Value,
    pub log: String,
    pub tags: Vec<Tag>
}

pub struct Service {
    data_path: String,
    index_map: RwLock<HashMap<String, Index>>
}

impl Service {
    pub async fn new(data_path: &str) -> Self {
        fs::create_dir_all(data_path).unwrap();
        let mut map: HashMap<String, Index> = HashMap::new();
        let dirs = fs::read_dir(data_path).unwrap();
        for entry in dirs {
            let path = entry.unwrap().path();
            if path.is_dir() {
                if let Some(name) = path.file_name().and_then(|s| s.to_str()) {
                    map.insert(name.to_string(), Index::new(data_path, name));
                }
            }
        }

        let service = Service {
            data_path: data_path.to_string(),
            index_map: RwLock::new(map)
        };
        service.mapping::<IndexMapping>().await.expect("failed to mapping IndexMapping");
        service
    }

    pub fn get_indices(&self) -> Option<Vec<String>> {
        let guard = self.get_map_read_guard().ok()?;
        Some(guard.keys().map(|x| x.to_string()).collect())
    }

    pub async fn get_mapping(&self, log_type: &LogType, name: &str) -> Option<IndexMapping> {
        match self.get_mappings(log_type).await {
            Ok(mappings) => {
                mappings.into_iter().find(|x| x.name == name)
            }
            Err(e) => {
                warn!("failed to get mappings of {log_type}");
                None
            }
        }
    }

    /// get index mappings by log type(Json/Raw)
    pub async fn get_mappings(&self, log_type: &LogType) -> Result<Vec<IndexMapping>, Box<dyn Error>> {
        let guard = self.get_map_read_guard()?;
        match guard.get(INDEX_MAPPING_INDEX_NAME) {
            None => { Ok(Vec::new()) }
            Some(index) => {
                let mappings: Vec<IndexMapping> = index.search_logs(&format!("log_type = '{log_type}'"),
                        Box::new(|log, _| { serde_json::from_str::<IndexMapping>(log).ok() }))?
                    .iter().filter(|x| x.is_some())
                    .map(|x| x.as_ref().unwrap())
                    .cloned()
                    .collect();
                Ok(mappings)
            }
        }
    }

    pub async fn get_tag_values(&self, name: &str, label: &str) -> Option<Vec<String>> {
        let guard = self.get_map_read_guard().ok()?;
        match guard.get(name) {
            None => { Some(vec!()) }
            Some(index) => {
                index.get_tag_values(label)
            }
        }
    }

    /// determine whether the mapping has changed
    pub async fn has_mapping_changed(&self, mapping: &IndexMapping) -> Result<bool, Box<dyn Error>> {
        let mappings = self.get_mappings(&LogType::Json).await?;
        if let Some(m) = mappings.iter().find(|x| x.name == mapping.name) {
            if m.log_type != mapping.log_type {
                return Err(format!("can not change log_type of {} from {} to {}", m.name, m.log_type, mapping.log_type).into());
            }
            let diff: Vec<&FieldMapping> = m.fields.iter()
                .merge_join_by(mapping.fields.iter(), Ord::cmp)
                .filter_map(|e| match e {
                    Left(x) | Right(x) => Some(x),
                    Both(_, _) => None,
                })
                .collect();
            return Ok(m.log_regex != mapping.log_regex || !diff.is_empty());
        }

        Ok(true)
    }

    /// save the json of instance as `Json log` based on mapping
    pub fn index<T>(&self, t: &T) -> Result<(), Box<dyn Error>>
    where
        T : TalogIndex + 'static {
        let mut guard = self.get_map_write_guard()?;
        let index_name = T::index_name();
        let tags = Self::parse_tags::<T>(t);
        guard.entry(index_name.to_string())
            .or_insert_with(|| { Index::new(self.data_path.as_str(), index_name) })
            .push(&tags, &vec![serde_json::to_string(t)?])
    }

    /// save log
    pub async fn index_log(&self, log_type: &LogType, name: &str, tags: &Vec<Tag>,
                     parse: bool, log: &str) -> Result<(), Box<dyn Error>> {
        let mapping = self.get_mapping(log_type, name).await
            .ok_or(format!("please maintain the mapping of {name} first"))?;
        self.index_log_with_mapping(&mapping, tags, parse, log)
    }

    /// save logs
    /// 
    /// when you choose not to parse, all logs will be written at once, resulting in the highest performance
    pub async fn index_logs(&self, log_type: &LogType, name: &str, tags: &Vec<Tag>,
                            parse: bool, logs: &Vec<String>) -> Result<(), Box<dyn Error>> {
        if parse {
            for log in logs {
                if let Err(e) = self.index_log(log_type, name, tags, parse, log).await {
                    warn!("failed to index log({log}) into {name}: {e}");
                }
            }
            Ok(())
        } else {
            self.index_raw_logs(name, tags, logs)
        }
    }

    pub fn index_log_with_mapping(&self, mapping: &IndexMapping, tags: &Vec<Tag>, parse: bool, log: &str)
        -> Result<(), Box<dyn Error>> {
        if parse {
            if mapping.log_type == LogType::Json {
                return self.index_json_log(mapping, tags, log);
            }

            if mapping.log_regex.is_some() {
                return self.index_log_with_regex(mapping, tags, log);
            }
        }

        self.index_raw_logs(&mapping.name, tags, &vec![log.to_string()])
    }

    /// generate an index mapping relationship based on the reflection characteristics of the type
    ///
    /// # Example
    /// ```
    /// #[derive(TalogIndex)]
    /// #[index("index_mapping")]
    /// pub struct IndexMapping {
    ///     pub fields: Vec<FieldMapping>,
    ///     pub log_regex: Option<String>,
    ///     #[tag]
    ///     pub log_type: LogType,
    ///     pub mapping_time: i64,
    ///     pub name: String
    /// }
    /// ```
    pub async fn mapping<T>(&self) -> Result<(), Box<dyn Error>>
    where
        T : TalogIndex + 'static {
        let mapping = Self::parse_mapping::<T>();
        if self.has_mapping_changed(&mapping).await? {
            self.index(&mapping)?;
        }
        Ok(())
    }

    /// parse mapping of the generic type T that implements TalogIndex
    pub fn parse_mapping<T: TalogIndex + 'static>() -> IndexMapping {
        IndexMapping {
            fields: T::field_mappings().iter().cloned().collect(),
            log_regex: None,
            log_type: LogType::Json,
            mapping_time: Utc::now().timestamp(),
            name: T::index_name().to_string()
        }
    }

    /// parse tags of instance based on mapping
    pub fn parse_tags<T: TalogIndex + 'static>(t: &T) -> Vec<Tag> {
        let mappings = T::field_mappings();
        match serde_json::to_value(t) {
            Ok(value) => {
                let mut tags: Vec<Tag> = Vec::new();
                for mapping in mappings.iter().filter(|x| x.is_tag) {
                    if let Some(v) = value.get(&mapping.name) {
                        tags.push(Tag {
                            label: mapping.name.clone(),
                            value: v.as_str()
                                .map(|s| s.to_string())
                                .unwrap_or_else(|| v.to_string())
                        })
                    }
                }
                tags
            }
            Err(_) => { Vec::new() }
        }
    }

    /// remove all bucket files of specified index but index file and index mapping
    pub fn remove_index(&self, name: &str) -> Result<(), Box<dyn Error>> {
        let mut guard = self.get_map_write_guard()?;
        if let Some(index) = guard.remove(name) {
            index.clean()?;
        }
        Ok(())
    }

    /// search logs by expr, please refer to [fexpr](https://github.com/mnaufalhilmym/fexpr) for expr rules
    pub async fn search_logs(&self, log_type: &LogType, name: &str, expr: &str) -> Result<Vec<LogModel>, Box<dyn Error>> {
        match self.get_mapping(log_type, name).await {
            Some(mapping) => {
                let begin = Utc::now();
                let guard = self.get_map_read_guard()?;
                match guard.get(name) {
                    Some(index) => {
                        let result: Vec<LogModel> = match log_type {
                            LogType::Json => {
                                index.search_logs(expr, Box::new(|log, tags| {LogModel {
                                    data: serde_json::from_str::<Value>(log).unwrap_or_default(),
                                    log: log.to_string(),
                                    tags: tags.to_vec()
                                }}))?
                            }
                            LogType::Raw => {
                                match &mapping.log_regex {
                                    None => {
                                        index.search_logs(expr, Box::new(|log, tags| {LogModel {
                                            data: Value::Null,
                                            log: log.to_string(),
                                            tags: tags.to_vec()
                                        }}))?
                                    }
                                    Some(log_regex) => {
                                        let reg = Regex::new(log_regex)?;
                                        let names: Vec<String> = reg.capture_names()
                                            .filter_map(|x| x)
                                            .map(|x| x.to_string())
                                            .collect();
                                        index.search_logs(expr, Box::new(|log, tags| {
                                            match reg.captures(log) {
                                                None => {LogModel {
                                                    data: Value::Null,
                                                    log: log.to_string(),
                                                    tags: tags.to_vec()
                                                }}
                                                Some(caps) => {
                                                    let mut map: HashMap<String, String> = HashMap::new();
                                                    for name in &names {
                                                        if let Some(m) = caps.name(&name) {
                                                            map.insert(name.to_string(), m.as_str().to_string());
                                                        }
                                                    }
                                                    LogModel {
                                                        data: json!(map),
                                                        log: log.to_string(),
                                                        tags: tags.to_vec()
                                                    }
                                                }
                                            }
                                        }))?
                                    }
                                }
                            }
                        };
                        debug!("search {name} logs by {expr}, total logs: {}, elapsed: {}", result.len(), Utc::now() - begin);
                        Ok(result)
                    }
                    None => {
                        Ok(vec!())
                    }
                }
            }
            None => { Err(format!("please maintain the mapping of {name} first").into()) }
        }
    }

    fn get_map_read_guard(&self) -> Result<RwLockReadGuard<HashMap<String, Index>>, Box<dyn Error>> {
        Ok(self.index_map.read()
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?)
    }

    fn get_map_write_guard(&self) -> Result<RwLockWriteGuard<HashMap<String, Index>>, Box<dyn Error>> {
        Ok(self.index_map.write()
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?)
    }

    fn index_json_log(&self, mapping: &IndexMapping, tags: &Vec<Tag>, log: &str) -> Result<(), Box<dyn Error>> {
        let mut tags: Vec<Tag> = tags.iter().cloned().collect();
        let json: Value = serde_json::from_str(log)?;
        for field in mapping.fields.iter().filter(|x| x.is_tag) {
            if tags.iter().any(|x| x.label == field.name) {
                continue;
            }

            let value = json.get(&field.name).and_then(|x| x.as_str()).map(|x| x.to_string());
            if let Some(value) = value {
                tags.push(Tag {
                    label: field.name.clone(),
                    value
                });
            }
        }
        
        self.index_raw_logs(&mapping.name, &tags, &vec![log.to_string()])
    }

    fn index_log_with_regex(&self, mapping: &IndexMapping, mut tags: &Vec<Tag>, log: &str) -> Result<(), Box<dyn Error>> {
        let mut tags: Vec<Tag> = tags.iter().cloned().collect();
        let reg = Regex::new(mapping.log_regex
            .as_ref()
            .unwrap())?;
        if let Some(caps) = reg.captures(log) {
            for field in mapping.fields.iter().filter(|x| x.is_tag) {
                if tags.iter().any(|x| x.label == field.name) {
                    continue;
                }

                if let Some(m) = caps.name(&field.name) {
                    tags.push(Tag {
                        label: field.name.clone(),
                        value: m.as_str().to_string()
                    });
                }
            }
        }

        self.index_raw_logs(&mapping.name, &tags, &vec![log.to_string()])
    }

    fn index_raw_logs(&self, name: &str, tags: &Vec<Tag>, logs: &Vec<String>) -> Result<(), Box<dyn Error>> {
        let mut guard = self.get_map_write_guard()?;
        guard.entry(name.to_string())
            .or_insert_with(|| Index::new(&self.data_path, name))
            .push(&tags, logs)?;
        Ok(())
    }
}