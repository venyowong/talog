use std::collections::HashMap;
use fexpr::SignOp;
use serde::{Deserialize, Serialize};
use crate::Bucket;

/// Shard is used to organize all Buckets under a certain type of label
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Shard {
    pub buckets: HashMap<String, HashMap<String, Bucket>>
}

impl Shard {
    pub fn new() -> Shard {
        Shard {
            buckets: HashMap::new()
        }
    }

    pub fn append_bucket(&mut self, value: &str, bucket: &Bucket) {
        self.buckets
            .entry(value.to_string())
            .or_default()
            .insert(bucket.key.clone(), bucket.clone());
    }

    pub fn get_buckets(&self, value: &str) -> Option<Vec<Bucket>> {
        if value.len() == 0 {
            Some(self.buckets.values()
                .flat_map(|b| b.values())
                .cloned()
                .collect())
        } else {
            self.buckets.get(value)
                .map(|b| b.values().cloned().collect())
        }
    }

    pub fn get_buckets_by_condition(&self, op: &SignOp, value: &str) -> Option<Vec<Bucket>> {
        match op {
            SignOp::None => {
                None
            }
            SignOp::Eq | SignOp::AnyEq => {
                self.get_buckets(value)
            }
            SignOp::Neq | SignOp::AnyNeq => {
                Some(self.buckets.iter().filter(|x| x.0 != value)
                    .map(|x| x.1.values().cloned())
                    .flatten()
                    .collect())
            }
            SignOp::Like | SignOp::AnyLike => {
                Some(self.buckets.iter().filter(|x| x.0.contains(value))
                    .map(|x| x.1.values().cloned())
                    .flatten()
                    .collect())
            }
            SignOp::Nlike | SignOp::AnyNlike => {
                Some(self.buckets.iter().filter(|x| !x.0.contains(value))
                    .map(|x| x.1.values().cloned())
                    .flatten()
                    .collect())
            }
            SignOp::Lt | SignOp::AnyLt => {
                Some(self.buckets.iter().filter(|x| x.0.as_str() < value)
                    .map(|x| x.1.values().cloned())
                    .flatten()
                    .collect())
            }
            SignOp::Lte | SignOp::AnyLte => {
                Some(self.buckets.iter().filter(|x| x.0.as_str() <= value)
                    .map(|x| x.1.values().cloned())
                    .flatten()
                    .collect())
            }
            SignOp::Gt | SignOp::AnyGt => {
                Some(self.buckets.iter().filter(|x| x.0.as_str() > value)
                    .map(|x| x.1.values().cloned())
                    .flatten()
                    .collect())
            }
            SignOp::Gte | SignOp::AnyGte => {
                Some(self.buckets.iter().filter(|x| x.0.as_str() >= value)
                    .map(|x| x.1.values().cloned())
                    .flatten()
                    .collect())
            }
        }
    }

    pub fn get_values(&self) -> Vec<String> {
        self.buckets.keys().cloned().collect()
    }

    pub fn remove_bucket(&mut self, value: &str, bucket_key: &str) {
        if let Some(map) = self.buckets.get_mut(value) {
            map.remove(bucket_key);
        }
    }
}