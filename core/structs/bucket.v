module structs

import arrays
import crypto.md5
import venyowong.linq
import os
import sync

pub struct Bucket {
pub:
	file string
	index string
	key string
	tags []Tag
}

pub struct BucketSet {
mut:
	buckets []Bucket
	mutex sync.RwMutex @[json: '-']
}

pub fn Bucket.new(index string, path string, tags []Tag) !Bucket {
	mut strs := arrays.map_indexed[Tag, string](tags, fn (i int, t Tag) string {return "$t.label:$t.value"})
	str := linq.join(linq.order(mut strs, |x, y| x > y), ";")
	mut hasher := md5.new()
    hasher.write(str.bytes())!
    hash_bytes := hasher.sum([]u8{})
	key := hash_bytes.hex()
	file := os.join_path(path, key + ".log")
	return Bucket {
		file: file
		index: index
		key: key
		tags: tags
	}
}

pub fn (mut s BucketSet) append(b Bucket) bool {
	s.mutex.lock()
	defer {s.mutex.unlock()}

	if b !in s.buckets {
		s.buckets << b
		return true
	}

	return false
}

pub fn (mut s BucketSet) list() []Bucket {
	s.mutex.rlock()
	defer {s.mutex.runlock()}

	return s.buckets
}

pub fn (mut s BucketSet) remove(key string) {
	s.mutex.lock()
	defer {s.mutex.unlock()}

	s.buckets = s.buckets.filter(fn [key] (x Bucket) bool { return x.key != key })
}