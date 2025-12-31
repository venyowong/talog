module structs

import venyowong.concurrent
import venyowong.linq

pub struct Shard {
mut:
	m concurrent.AsyncMap[BucketSet]
}

pub fn (mut s Shard) append_bucket(value string, b Bucket) bool {
	mut set := s.m.get_or_create(value, fn () BucketSet { return BucketSet{} })
	return set.append(b)
}

pub fn (mut s Shard) get_buckets(value string) []Bucket {
	if value.len > 0 {
		mut set := s.m.get(value) or {return []Bucket{}}
		return set.list()
	}

	mut result := []Bucket{}
	for k in s.m.keys() {
		mut set := s.m.get(k) or {continue}
		result = linq.union(result, set.list())
	}
	return result
}

pub fn (mut s Shard) get_values() []string {
	return s.m.keys()
}

pub fn (mut s Shard) remove_bucket(value string, bucket_key string) {
	mut set := s.m.get(value) or {return}
	set.remove(bucket_key)
}