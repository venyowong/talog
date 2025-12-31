module core

import json
import log
import structs
import os
import sync
import time
import venyowong.concurrent
import venyowong.file
import venyowong.linq
import venyowong.query

pub struct Index {
	index_file string = 'index.json' @[json: '-']
mut:
	index_file_path string @[json: '-']
	mutex sync.RwMutex @[json: '-']
	need_save bool @[json: '-']
	path string @[json: '-']
	wg &sync.WaitGroup = sync.new_waitgroup() @[json: '-']
pub mut:
	buckets map[string]structs.Bucket
	name string
	shards concurrent.AsyncMap[structs.Shard]
}

pub fn (mut index Index) setup(base_path string) ! {
	index.path = os.join_path(base_path, index.name)
	if !os.exists(index.path) || !os.is_dir(index.path) {
		os.mkdir_all(index.path)!
	}

	log.info("Talog index [$index.name] setup...")
	index.index_file_path = os.join_path(index.path, index.index_file)
	if !os.exists(index.index_file_path) {
		return
	}

	content := os.read_file(index.index_file_path) or {
		log.error("Cannot read $index.index_file_path: $err")
		return
	}
	index_object := json.decode(Index, content) or {
		log.error("Cannot decode $index.index_file_path: $err")
		return
	}
	index.shards = index_object.shards
	index.buckets = index_object.buckets.clone()
}

pub fn (mut idx Index) close() ! {
	idx.mutex.lock()
	defer {idx.mutex.unlock()}

	idx.save()!
}

pub fn (mut idx Index) destroy() ! {
	idx.mutex.lock()
	defer {idx.mutex.unlock()}

	file.close_channels()
	os.rmdir_all(idx.path)!
}

pub fn (mut index Index) get_all_logs[T](map_log fn (line string, tags []structs.Tag) T) ![]T {
	mut result := []T{}
	for bucket in index.buckets.values() {
		logs := file.read_by_line[T](bucket.file, fn [bucket, map_log] [T] (line string) ?T {
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

	mut s := index.shards.get(tag.label) or { return []structs.Bucket{} }
	return s.get_buckets(tag.value)
}

pub fn (mut index Index) get_logs[T](buckets []structs.Bucket, map_log fn (line string, tags []structs.Tag) T) ![]T {
	mut result := []T{}
	for bucket in buckets {
		logs := file.read_by_line[T](bucket.file, fn [bucket, map_log] [T] (line string) ?T {
			return map_log(line, bucket.tags)
		})!
		result << logs
	}
	return result
}

pub fn (mut index Index) get_tag_values(label string) []string {
	index.mutex.rlock()
	defer {index.mutex.runlock()}

	mut s := index.shards.get(label) or { return []string{} }
	return s.get_values()
}

pub fn (mut index Index) push(tags []structs.Tag, logs ...string) {
	bucket := structs.Bucket.new(index.name, index.path, tags) or {
		log.error("failed to new bucket $index.name $index.path $tags")
		return
	}
	if !os.exists(bucket.file) {
		for tag in tags {
			mut s := index.shards.get_or_create(tag.label, fn () structs.Shard { return structs.Shard{} })
			if s.append_bucket(tag.value, bucket) {
				index.need_save = true
			}
		}

		spawn index.flush()
	}
	file.append_by_chan(bucket.file, ...logs)
	index.buckets[bucket.key] = bucket
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
		mut s := index.shards.get(tag.label) or {continue}
		s.remove_bucket(tag.value, key)
	}

	file.close_channel(bucket.file)
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

	log.debug("Talog index [$index.name] saving...")
	os.write_file(index.index_file_path, json.encode(index))!
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
		logs := file.read_by_line[T](bucket.file, fn [bucket, map_log] [T] (line string) ?T {
			return map_log(line, bucket.tags)
		})!
		result << logs
	}
	return result
}

fn (mut index Index) flush() {
	time.sleep(1000 * time.millisecond)
	index.wg.wait()
	if !index.need_save {
		return
	}
	// wait group is all done, this thread can hold write lock
	index.mutex.lock()
	defer {index.mutex.unlock()}
	if !index.need_save {
		return
	}

	index.save() or {
		log.warn("failed to save index $index.name: $err")
		return
	}

	index.need_save = false
}