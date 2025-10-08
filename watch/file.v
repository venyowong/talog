module watch

import core
import core.structs
import os
import time
import venyowong.concurrent
import venyowong.file

pub struct FileInfo {
pub mut:
	index string
	last_mtime i64
	next_pos u64
	path string
	tags []structs.Tag
	update bool @[json: '-']
	watcher ?file.Watcher @[json: '-']
}

pub struct DirInfo {
mut:
	t ?thread
pub mut:
	dir string
	files concurrent.SafeStructMap[FileInfo]
	index string
	tags []structs.Tag
}

pub struct FileWatcher {
	dir_watch_interval i64 = 5 * time.second
mut:
	threads []thread
pub mut:
	dirs concurrent.SafeStructMap[DirInfo]
	files []FileInfo
	service &core.Service
}

pub fn (mut w FileWatcher) watch_dir(dir string, index string, tags []structs.Tag) {
	real_dir := os.real_path(dir)
	mut info := w.dirs.get_or_create(real_dir, fn () DirInfo {return DirInfo{}})
	if info.t == none {
		info.dir = real_dir
		info.index = index
		info.tags = tags
		info.t = spawn watch_dir_inner(info, w.dir_watch_interval)
	} else {
		info.index = index
		info.tags = tags
	}
}

pub fn (mut w FileWatcher) watch_dir_inner(info &DirInfo, interval i64) {
	for {
		files := os.ls(info.dir) or {
			time.sleep(interval)
			continue
		}

		// remove deleted files
		keys := info.files.keys()
		for k in keys {
			if k !in files {
				file_info := info.files.remove(k) or {continue}
				file_info.watcher.stop()
			}
		}

		// watch new files
		for f in files {
			if f !in info.files {
				path := os.join_path(info.dir, f)
				file_info := FileInfo {
					index: info.index
					path: path
					tags: info.tags
				}
				index := w.service.get_or_create_index(file_info.index)
				file_info.watcher = file.Watcher {
					path: path
					on_data: fn [file_info, index] (bytes []u8) bool {

					}
				}
				info.files.set(f, )
			}
		}
	}
}