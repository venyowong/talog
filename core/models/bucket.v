module models

import arrays
import crypto.md5
import venyowong.linq
import os

pub struct Bucket {
pub mut:
	index string @[json: Index]
	key string @[json: Key]
	tags []Tag @[json: Tags]
	file string @[json: File]
}

pub fn Bucket.new(index string, path string, tags []Tag) !Bucket {
	mut strs := arrays.map_indexed[Tag, string](tags, fn (i int, t Tag) string {return "$t.label:$t.value"})
	str := linq.join(linq.order(mut strs, |x, y| x > y), ";")
	mut hasher := md5.new()
    hasher.write(str.bytes())!
    hash_bytes := hasher.sum([]u8{})
	key := hash_bytes.hex()
	return Bucket {
		index: index,
		tags: tags,
		key: key,
		file: os.join_path(path, key + ".log")
	}
}