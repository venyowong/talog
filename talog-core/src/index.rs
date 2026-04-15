use std::collections::HashMap;
use std::error::Error;
use std::{fs};
use std::fs::{File};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::sync::{RwLock};
use fexpr::{ExprGroupItem, JoinOp};
use itertools::Itertools;
use log::warn;
use crate::{file, Bucket, Shard, Tag};

const INDEX_FILE: &str = "index.json";

pub struct Index {
    path: PathBuf,
    shards: RwLock<HashMap<String, Shard>>
}

pub type LogMapper<'a, T> = Box<dyn Fn (&str, &Vec<Tag>) -> T + 'a>;

impl Index {
    pub fn new(base_path: &str, name: &str) -> Self {
        let base_path = PathBuf::from(base_path);
        let path = base_path.join(name);
        if !path.exists() {
            fs::create_dir_all(&path).unwrap();
        }
        let index_file_path = path.join(INDEX_FILE);
        let mut idx = Self {
            path,
            shards: RwLock::new(HashMap::new())
        };
        if !index_file_path.exists() {
            return idx;
        }

        idx.load_from_index_file();
        idx
    }

    pub fn clean(&self) -> Result<(), Box<dyn Error>> {
        let mut guard = self.shards.write()
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;
        let buckets: Vec<Bucket> = guard.values()
            .filter_map(|x| x.get_buckets(""))
            .flatten()
            .unique_by(|x| x.key.clone())
            .collect();
        for bucket in buckets {
            file::remove_file(&bucket.file)?;
        }
        guard.clear();
        Ok(())
    }

    /// get all logs from all buckets
    pub fn get_all_logs<'a, T>(&self, log_mapper: LogMapper<'a, T>) -> Result<Vec<T>, Box<dyn Error>> {
        let guard = self.shards.read()
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;
        let mut buckets: Vec<Bucket> = Vec::new();
        for shard in guard.values() {
            let bs = shard.get_buckets("")
                .ok_or("failed to get all buckets")?;
            for b in bs {
                if !buckets.contains(&b) {
                    buckets.push(b);
                }
            }
        }
        Self::get_logs(&buckets, log_mapper)
    }

    /// get buckets corresponding to the specified tag
    pub fn get_buckets(&self, tag: &Tag) -> Option<Vec<Bucket>> {
        let shards = self.shards.read().ok()?;
        let shard = shards.get(&tag.label)?;
        shard.get_buckets(&tag.value)
    }

    /// get all existing values of the tag with specified label
    pub fn get_tag_values(&self, label: &str) -> Option<Vec<String>> {
        let shards = self.shards.read().ok()?;
        let shard = shards.get(label)?;
        Some(shard.buckets.keys().cloned().collect())
    }

    /// index logs with same tags
    pub fn push(&mut self, tags: &Vec<Tag>, logs: &Vec<String>) -> Result<(), Box<dyn Error>> {
        let bucket = Bucket::new(self.path.to_str().unwrap(), &tags);

        if !fs::exists(&bucket.file)? {
            for tag in tags {
                self.shards.write()
                    .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?
                    .entry(tag.label.clone())
                    .or_default()
                    .append_bucket(&tag.value, &bucket);
            }
            if let Err(e) = self.store_index_file() {
                warn!("failed to store index file({}): {e}", self.path.to_string_lossy().to_string());
            }
        }

        for log in logs {
            if let Err(e) = file::append_line(&bucket.file, log) {
                warn!("failed to append log into {}: {e}", &bucket.file);
            }
        }

        Ok(())
    }

    /// remove buckets by expr, please refer to [fexpr](https://github.com/mnaufalhilmym/fexpr) for expr rules
    pub fn remove(&self, expr: &str) -> Result<(), Box<dyn Error>> {
        let groups = fexpr::parse(expr)?;
        let buckets = self.search(&ExprGroupItem::ExprGroups(groups))
            .ok_or(format!("failed to search buckets by expr: {}", expr))?;
        for bucket in buckets {
            if let Err(e) = self.remove_bucket(&bucket) {
                warn!("failed to remove bucket {}: {e}", &bucket.file);
            }
        }
        Ok(())
    }

    /// remove the specified bucket will drop the data in memory and delete the corresponding file
    pub fn remove_bucket(&self, bucket: &Bucket) -> Result<(), Box<dyn Error>> {
        for tag in &bucket.tags {
            if let Some(shard) = self.shards.write()
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?
                .get_mut(&tag.label) {
                shard.remove_bucket(&tag.value, &bucket.key);
            }
        }
        file::remove_file(&bucket.file)?;
        Ok(())
    }

    pub fn search(&self, expr_group: &ExprGroupItem) -> Option<Vec<Bucket>> {
        match expr_group {
            ExprGroupItem::Expr(expr) => {
                self.shards.read()
                    .ok()?
                    .get(expr.left.literal())?
                    .get_buckets_by_condition(&expr.op, expr.right.literal())
            }
            ExprGroupItem::ExprGroups(groups) => {
                let mut buckets: Vec<Option<Vec<Bucket>>> = Vec::new();
                let mut ops : Vec<JoinOp> = Vec::new();
                for g in groups.get() {
                    buckets.push(self.search(&g.item));
                    if buckets.len() > 1 { // ignore first op
                        ops.push(g.join)
                    }
                }

                // deal and op
                for i in 0..ops.len() {
                    let i = ops.len() - i - 1;
                    match ops[i] {
                        JoinOp::And => {
                            match &buckets[i] {
                                None => { buckets[i] = None; }
                                Some(bs1) => {
                                    match &buckets[i+1] {
                                        None => { buckets[i] = None; }
                                        Some(bs2) => {
                                            buckets[i] = Some(bs1.iter().filter(|x| bs2.contains(x)).cloned().collect());
                                        }
                                    }
                                }
                            }
                            buckets.remove(i + 1);
                        }
                        JoinOp::Or => {continue}
                    }
                }

                // deal or op
                for i in 0..buckets.len()-1 {
                    match &buckets[i] {
                        None => {continue}
                        Some(bs1) => {
                            match &buckets[i+1] {
                                None => {continue}
                                Some(bs2) => {
                                    buckets[i+1] = Some(bs1.iter().chain(bs2).unique().cloned().collect())
                                }
                            }
                        }
                    }
                }

                buckets[buckets.len()-1].clone()
            }
        }
    }

    /// search logs by expr, please refer to [fexpr](https://github.com/mnaufalhilmym/fexpr) for expr rules
    pub fn search_logs<'a, T>(&self, expr: &str, log_mapper: LogMapper<'a, T>) -> Result<Vec<T>, Box<dyn Error>> {
        let groups = fexpr::parse(expr)?;
        let buckets = self.search(&ExprGroupItem::ExprGroups(groups));
        match buckets {
            None => { Ok(Vec::new()) }
            Some(buckets) => { Self::get_logs(&buckets, log_mapper) }
        }
    }

    fn get_logs<'a, T>(buckets: &[Bucket], log_mapper: LogMapper<'a, T>) -> Result<Vec<T>, Box<dyn Error>> {
        let mut result: Vec<T> = Vec::new();
        for bucket in buckets {
            let reader = BufReader::new(File::open(&bucket.file)?);
            for line in reader.lines() {
                result.push(log_mapper(&line?, &bucket.tags));
            }
        }
        Ok(result)
    }

    fn load_from_index_file(&mut self) {
        let index_file_path = self.path.join(INDEX_FILE);
        let shards: HashMap<String, Shard> = serde_json::from_str(&fs::read_to_string(index_file_path).unwrap()).unwrap();
        self.shards = RwLock::new(shards);
    }

    fn store_index_file(&self) -> Result<(), Box<dyn Error>> {
        let shards = self.shards.read()
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?
            .clone();
        let path = self.path.join(INDEX_FILE).to_string_lossy().to_string();
        file::overwrite(&path, &serde_json::to_string(&shards)?)
    }
}

impl Drop for Index {
    fn drop(&mut self) {
        if let Err(e) = self.store_index_file() {
            warn!("failed to store index file({}) when dropping: {e}", self.path.to_string_lossy().to_string());
        }
        if let Ok(mut guard) = self.shards.write() {
            guard.clear();
        }
    }
}