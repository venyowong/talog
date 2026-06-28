use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;
use std::{fs};
use std::fs::{File};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use anyhow::anyhow;
use fexpr::{ExprGroupItem, JoinOp};
use itertools::Itertools;
use log::warn;
use tokio::sync::RwLock;
use tokio::{self, time};
use crate::{file, Bucket, Shard, Tag};

const INDEX_FILE: &str = "index.json";

pub struct Index {
    path: PathBuf,
    shards: RwLock<HashMap<String, Shard>>
}

pub type LogMapper<'a, T> = Box<dyn Fn (&str, &Vec<Tag>) -> T + Send + 'a>;

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

    pub async fn clean(&self) -> Result<(), anyhow::Error> {
        let mut guard = self.shards.write().await;
        let buckets: Vec<Bucket> = guard.values()
            .filter_map(|x| x.get_buckets(""))
            .flatten()
            .unique_by(|x| x.key.clone())
            .collect();
        for bucket in buckets {
            file::remove_file(&bucket.file)?;
        }
        file::remove_file(self.path.join(INDEX_FILE).to_string_lossy().as_ref())?;
        guard.clear();
        Ok(())
    }

    /// get all logs from all buckets
    pub async fn get_all_logs<'a, T>(&self, log_mapper: LogMapper<'a, T>) -> Result<Vec<T>, anyhow::Error> {
        let guard = self.shards.read().await;
        let mut buckets: Vec<Bucket> = Vec::new();
        for shard in guard.values() {
            let bs = shard.get_buckets("")
                .ok_or(anyhow!("failed to get all buckets"))?;
            for b in bs {
                if !buckets.contains(&b) {
                    buckets.push(b);
                }
            }
        }
        Self::get_logs(&buckets, log_mapper).await
    }

    /// get buckets corresponding to the specified tag
    pub async fn get_buckets(&self, tag: &Tag) -> Option<Vec<Bucket>> {
        let shards = self.shards.read().await;
        let shard = shards.get(&tag.label)?;
        shard.get_buckets(&tag.value)
    }

    /// get all existing values of the tag with specified label
    pub async fn get_tag_values(&self, label: &str) -> Option<Vec<String>> {
        let shards = self.shards.read().await;
        let shard = shards.get(label)?;
        Some(shard.buckets.keys().cloned().collect())
    }

    /// index logs with same tags
    pub async fn push(&mut self, tags: &Vec<Tag>, logs: &Vec<String>) -> Result<(), anyhow::Error> {
        let bucket = Bucket::new(self.path.to_str().unwrap(), &tags);

        if !fs::exists(&bucket.file)? {
            for tag in tags {
                self.shards.write().await
                    .entry(tag.label.clone())
                    .or_default()
                    .append_bucket(&tag.value, &bucket);
            }
            if let Err(e) = self.store_index_file().await {
                warn!("failed to store index file({}): {e}", self.path.to_string_lossy().to_string());
            }
        }

        for log in logs {
            if let Err(e) = file::append_line(&bucket.file, log) {
                warn!("failed to append log into {}: {e}", &bucket.file);
            }
        }
        file::flush(&bucket.file)?;

        Ok(())
    }

    /// remove buckets by expr, please refer to [fexpr](https://github.com/mnaufalhilmym/fexpr) for expr rules
    pub async fn remove(&self, expr: &str) -> Result<(), anyhow::Error> {
        let groups = fexpr::parse(expr)?;
        let buckets = self.search(&ExprGroupItem::ExprGroups(groups))
            .await
            .ok_or(anyhow!("failed to search buckets by expr: {}", expr))?;
        for bucket in buckets {
            if let Err(e) = self.remove_bucket(&bucket).await {
                warn!("failed to remove bucket {}: {e}", &bucket.file);
            }
        }
        Ok(())
    }

    /// remove the specified bucket will drop the data in memory and delete the corresponding file
    pub async fn remove_bucket(&self, bucket: &Bucket) -> Result<(), anyhow::Error> {
        for tag in &bucket.tags {
            if let Some(shard) = self.shards.write().await
                .get_mut(&tag.label) {
                shard.remove_bucket(&tag.value, &bucket.key);
            }
        }
        file::remove_file(&bucket.file)?;
        Ok(())
    }

    pub async fn search(&self, expr_group: &ExprGroupItem) -> Option<Vec<Bucket>> {
        fn rec_search<'a>(
            this: &'a Index,
            expr_group: &'a ExprGroupItem,
        ) -> Pin<Box<dyn Future<Output = Option<Vec<Bucket>>> + Send + 'a>> {
            Box::pin(async move {
                match expr_group {
                    ExprGroupItem::Expr(expr) => {
                        this.shards.read()
                            .await
                            .get(expr.left.literal())?
                            .get_buckets_by_condition(&expr.op, expr.right.literal())
                    }
                    ExprGroupItem::ExprGroups(groups) => {
                        let mut buckets: Vec<Option<Vec<Bucket>>> = Vec::new();
                        let mut ops: Vec<JoinOp> = Vec::new();
                        for g in groups.get() {
                            buckets.push(rec_search(this, &g.item).await);
                            if buckets.len() > 1 {
                                ops.push(g.join)
                            }
                        }

                        // 处理 And
                        for i in (0..ops.len()).rev() {
                            match ops[i] {
                                JoinOp::And => {
                                    let res = match (&buckets[i], &buckets[i + 1]) {
                                        (Some(bs1), Some(bs2)) => Some(
                                            bs1.iter()
                                                .filter(|x| bs2.contains(x))
                                                .cloned()
                                                .collect(),
                                        ),
                                        _ => None,
                                    };
                                    buckets[i] = res;
                                    buckets.remove(i + 1);
                                }
                                JoinOp::Or => continue,
                            }
                        }

                        // 处理 Or
                        for i in 0..buckets.len().saturating_sub(1) {
                            let (left, right) = buckets.split_at_mut(i + 1);
                            match (&left[i], &mut right[0]) {
                                (Some(bs1), Some(bs2)) => {
                                    let combined: Vec<Bucket> = bs1
                                        .iter()
                                        .chain(bs2.iter())
                                        .unique()
                                        .cloned()
                                        .collect();
                                    *bs2 = combined;
                                }
                                _ => {}
                            }
                        }

                        buckets.last().cloned().flatten()
                    }
                }
            })
        }

        rec_search(self, expr_group).await
    }

    /// search logs by expr, please refer to [fexpr](https://github.com/mnaufalhilmym/fexpr) for expr rules
    pub async fn search_logs<'a, T>(&self, expr: &str, log_mapper: LogMapper<'a, T>) -> Result<Vec<T>, anyhow::Error> {
        if expr.is_empty() {
            return self.get_all_logs(log_mapper).await;
        }

        let groups = fexpr::parse(expr)?;
        let buckets = self.search(&ExprGroupItem::ExprGroups(groups)).await;
        match buckets {
            None => { Ok(Vec::new()) }
            Some(buckets) => { Self::get_logs(&buckets, log_mapper).await }
        }
    }

    async fn get_logs<'a, T>(buckets: &[Bucket], log_mapper: LogMapper<'a, T>) -> Result<Vec<T>, anyhow::Error> {
        let mut result: Vec<T> = Vec::new();
        for bucket in buckets {
            for i in 0..3 {
                match File::open(&bucket.file) {
                    Ok(file) => {
                        let reader = BufReader::new(file);
                        for line in reader.lines() {
                            let line = line?.replace("␤", "\n");
                            result.push(log_mapper(&line, &bucket.tags));
                        }
                        break;
                    },
                    Err(e) => {
                        warn!("failed to open {}, will retry {i}/3: {e}", &bucket.file);
                        time::sleep(Duration::from_millis(200)).await;
                    },
                }
            }
        }
        Ok(result)
    }

    fn load_from_index_file(&mut self) {
        let index_file_path = self.path.join(INDEX_FILE);
        let shards: HashMap<String, Shard> = serde_json::from_str(&fs::read_to_string(index_file_path).unwrap()).unwrap();
        self.shards = RwLock::new(shards);
    }

    async fn store_index_file(&self) -> Result<(), anyhow::Error> {
        let shards = self.shards.read().await.clone();
        let path = self.path.join(INDEX_FILE).to_string_lossy().to_string();
        file::overwrite(&path, &serde_json::to_string(&shards)?)
    }
}