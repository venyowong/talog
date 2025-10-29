module core

import json
import log
import structs
import os
import sync
import time
import venyowong.concurrent
import venyowong.linq
import venyowong.query

pub struct Index {
	index_file string = 'index.json' @[json: '-']
mut:
	index_file_path string @[json: '-']
	log log.Log @[json: '-']
	mutex sync.RwMutex @[json: '-']
	need_save bool @[json: '-']
	path string @[json: '-']
	safe_file concurrent.SafeFile = concurrent.SafeFile{} @[json: '-']
	wg &sync.WaitGroup = sync.new_waitgroup() @[json: '-']
pub mut:
	name string
	tries map[string]&structs.Trie
	buckets map[string]structs.Bucket
}

pub fn (mut index Index) setup(base_path string) ! {
	index.path = os.join_path(base_path, index.name)
	if !os.exists(index.path) || !os.is_dir(index.path) {
		os.mkdir_all(index.path)!
	}

	index.log.set_level(.info)
	index.log.set_full_logpath(os.join_path(index.path, "log.txt"))
	index.log.log_to_console_too()
	index.log.info("Talog index [$index.name] setup...")
	defer {index.log.flush()}
	index.index_file_path = os.join_path(index.path, index.index_file)
	if !os.exists(index.index_file_path) {
		return
	}

	content := os.read_file(index.index_file_path) or {
		index.log.error("Cannot read $index.index_file_path: $err")
		return
	}
	index_object := json.decode(Index, content) or {
		index.log.error("Cannot decode $index.index_file_path: $err")
		return
	}
	index.tries = index_object.tries.clone()
	index.buckets = index_object.buckets.clone()
}

pub fn (mut index Index) get_all_logs[T](map_log fn (line string, tags []structs.Tag) T) ![]T {
	mut result := []T{}
	for bucket in index.buckets.values() {
		logs := index.safe_file.read_by_line[T](bucket.file, fn [bucket, map_log] [T] (line string) ?T {
			return map_log(line, bucket.tags)
		})!
		result << logs
	}
	return result
}

pub fn (mut index Index) get_buckets(tag structs.Tag) []structs.Bucket {
	index.mutex.rlock()
	defer {index.mutex.runlock()}

	if tag.label.len == 0 {
		return index.buckets.values()
	}
	if tag.label !in index.tries {
		return []structs.Bucket{}
	}

	mut trie := unsafe{index.tries[tag.label]}
	if trie.is_default() {
		index.tries[tag.label] = &trie
	}
	return trie.get_buckets(tag.value)
}

pub fn (mut index Index) get_logs[T](buckets []structs.Bucket, map_log fn (line string, tags []structs.Tag) T) ![]T {
	mut result := []T{}
	for bucket in buckets {
		logs := index.safe_file.read_by_line[T](bucket.file, fn [bucket, map_log] [T] (line string) ?T {
			return map_log(line, bucket.tags)
		})!
		result << logs
	}
	return result
}

pub fn (mut index Index) get_tag_values(label string) []string {
	index.mutex.rlock()
	defer {index.mutex.runlock()}
	if label !in index.tries {
		return []string{}
	}

	mut trie := unsafe{index.tries[label]}
	if trie.is_default() {
		index.tries[label] = &trie
	}
	return trie.get_leaves()
}

pub fn (mut index Index) push(tags []structs.Tag, logs ...string) {
	index.mutex.lock()
	index.wg.add(1)
	spawn index.flush()
	defer {
		index.wg.done()
		index.mutex.unlock()
	}

	bucket := structs.Bucket.new(index.name, index.path, tags) or {
		index.log.error("failed to new bucket $index.name $index.path $tags")
		return
	}
	index.buckets[bucket.key] = bucket
	index.safe_file.append(bucket.file, ...logs) or {
		index.log.error("failed to append logs to file $bucket.file")
		return
	}

	for tag in tags {
		mut trie := &structs.Trie{}
		if tag.label !in index.tries {
			index.tries[tag.label] = trie
		} else {
			trie = unsafe{index.tries[tag.label]}
		}
		if trie.append(tag.value, bucket) {
			index.need_save = true
		}
	}
}

pub fn (mut index Index) remove_bucket(key string) ! {
	index.mutex.lock()
	defer {index.mutex.unlock()}

	bucket := index.buckets[key] or {
		return
	}
	index.need_save = true
	index.wg.add(1)
	spawn index.flush()
	defer {index.wg.done()}

	for tag in bucket.tags {
		if tag.label !in index.tries {
			continue
		}

		mut trie := unsafe{index.tries[tag.label]}
		trie.remove_bucket(tag.value, key)
	}

	index.safe_file.rm(bucket.file)!
}

pub fn (mut index Index) remove(q query.Query) ! {
	buckets := index.search(q)!
	for bucket in buckets {
		index.remove_bucket(bucket.key) !
	}
}

pub fn (mut index Index) remove_by_exp(exp string) ! {
	q := query.Query.parse(exp)!
	index.remove(q)!
}

pub fn (mut index Index) save() ! {
	if !index.need_save {
		return
	}

	index.log.debug("Talog index [$index.name] saving...")
	index.safe_file.write_file(index.index_file_path, json.encode(index))!
}

pub fn (mut index Index) search(q query.Query) ![]structs.Bucket {
	match q {
		query.NoneQuery {
			return []structs.Bucket{}
		}
		query.EmptyQuery {
			return index.get_buckets(structs.Tag{})
		}
		query.BaseQuery {
			buckets := index.get_buckets(structs.Tag{
				label: q.key
				value: q.value
			})
			if q.ope == query.Symbol.eq {
				return buckets
			}
			if q.ope != query.Symbol.neq {
				return error("unsupported symbols $q.ope, for efficiency, talog.core.index only supports eq/neq")
			}

			all_buckets := index.get_buckets(structs.Tag{})
			if buckets.len == 0 {
				return all_buckets
			}

			return linq.except(all_buckets, buckets)
		}
		query.CompoundQuery {
			left_buckets := index.search(q.left)!
			right_buckets := index.search(q.right)!
			if q.ope == query.Symbol.and {
				if left_buckets.len == 0 || right_buckets.len == 0 {
					return []structs.Bucket{}
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

pub fn (mut index Index) search_logs[T](q query.Query, map_log fn (line string, tags []structs.Tag) T) ![]T {
	buckets := index.search(q)!
	mut result := []T{}
	for bucket in buckets {
		logs := index.safe_file.read_by_line[T](bucket.file, fn [bucket, map_log] [T] (line string) ?T {
			return map_log(line, bucket.tags)
		})!
		result << logs
	}
	return result
}

fn (mut index Index) flush() {
	time.sleep(100 * time.millisecond)
	index.log.debug("$index.name wg waiting...")
	index.wg.wait()
	index.log.debug("$index.name wg passed")
	if !index.need_save {
		return
	}
	// wait group is all done, this thread can hold write lock
	index.mutex.lock()
	defer {index.mutex.unlock()}
	index.log.debug("$index.name flush lock...")
	if !index.need_save {
		return
	}

	index.save() or {
		index.log.warn("failed to save index $index.name: $err")
		return
	}

	index.need_save = false
}