module core

import venyowong.concurrent
import json
import linq
import os
import sync

pub struct Index {
	index_file string = 'index.json'
mut:
	index_file_path string
	mutex sync.RwMutex
	need_save bool
	path string
	safe_file concurrent.SafeFile = concurrent.SafeFile{}
pub mut:
	name string @[json: Name]
	tries map[string]Trie @[json: Tries]
	buckets map[string]Bucket @[json: Buckets]
}

pub fn (mut index Index) setup(base_path string) ! {
	index.path = os.join_path(base_path, index.name)
	if !os.exists(index.path) || !os.is_dir(index.path) {
		os.mkdir_all(index.path)!
	}

	index.index_file_path = os.join_path(index.path, index.index_file)
	if !os.exists(index.index_file_path) {
		return
	}

	content := os.read_file(index.index_file_path) or {
		eprintln("Cannot read $index.index_file_path: $err")
		return
	}
	index_object := json.decode(Index, content) or {
		eprintln("Cannot decode $index.index_file_path: $err")
		return
	}
	index.tries = index_object.tries.clone()
	index.buckets = index_object.buckets.clone()
}

pub fn (mut index Index) get_buckets(tag Tag) []Bucket {
	index.mutex.rlock()
	defer {index.mutex.runlock()}

	if tag.label.len == 0 {
		return index.buckets.values()
	}

	mut trie := index.tries[tag.label] or {
		return []Bucket{}
	}
	return trie.get_buckets(tag.value)
}

pub fn (mut index Index) get_tag_values(label string) []string {
	index.mutex.rlock()
	defer {index.mutex.runlock()}

	mut trie := index.tries[label] or {
		return []string{}
	}
	return trie.get_leaves()
}

pub fn (mut index Index) push(tags []Tag, logs ...string) ! {
	index.mutex.lock()
	defer {index.mutex.unlock()}
	index.need_save = true

	bucket := Bucket.new(index.name, index.path, tags)!
	index.buckets[bucket.key] = bucket
	index.safe_file.append(bucket.file, ...logs)!

	for tag in tags {
		mut trie := index.tries[tag.label] or {
			t := Trie{}
			index.tries[tag.label] = t
			t
		}
		trie.append(tag.value, bucket)
	}
}

pub fn (mut index Index) save() ! {
	index.mutex.lock()
	defer {index.mutex.unlock()}

	if !index.need_save {
		return
	}

	index.safe_file.write_file(index.index_file_path, json.encode(index))!
}

pub fn (mut index Index) remove_bucket(key string) ! {
	index.mutex.lock()
	defer {index.mutex.unlock()}

	bucket := index.buckets[key] or {
		return
	}

	index.need_save = true
	for tag in bucket.tags {
		mut trie := index.tries[tag.label] or {
			continue
		}
		trie.remove_bucket(tag.value, key)
	}

	index.safe_file.rm(bucket.file)!
}

pub fn (mut index Index) remove(query Query) ! {
	buckets := index.search(query);
	for bucket in buckets {
		index.remove_bucket(bucket.key) !
	}
}

pub fn (mut index Index) search(query Query) []Bucket {
	match query {
		TagQuery {
			buckets := index.get_buckets(query.tag)
			if query.type == 0 {
				return buckets
			}

			all_buckets := index.get_buckets(Tag{})
			if buckets.len == 0 {
				return all_buckets
			}

			return linq.except(all_buckets, buckets)
		}
		ExpressionQuery {
			if query.left.is_default() && query.right.is_default() {
				return index.get_buckets(Tag{})
			}

			left_buckets := index.search(query.left)
			right_buckets := index.search(query.right)
			if query.type == 2 {
				if left_buckets.len == 0 || right_buckets.len == 0 {
					return []Bucket{}
				}

				return linq.intersect(left_buckets, right_buckets)
			}

			if left_buckets.len == 0 {
				return right_buckets
			}
			if right_buckets.len == 0 {
				return left_buckets
			}

			return linq.union(left_buckets, right_buckets)
		}
	}
}

pub fn (mut index Index) search_logs[T](query Query, map_log fn (line string, tags []Tag) T) ![]T {
	mut result := []T{}
	buckets := index.search(query)
	for bucket in buckets {
		logs := index.safe_file.read_by_line[T](bucket.file, fn [bucket, map_log] [T] (line string) ?T {
			return map_log(line, bucket.tags)
		})!
		result << logs
	}
	return result
}