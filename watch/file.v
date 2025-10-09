module watch

import core
import core.meta
import core.structs
import log
import os
import time
import venyowong.concurrent
import venyowong.file
import venyowong.query

pub struct FileInfo {
pub mut:
	index string
	path string
	rule LogRule
	tags []structs.Tag
	watcher ?file.Watcher @[json: '-']
}

pub struct DirInfo {
mut:
	t ?thread
pub mut:
	dir string
	files concurrent.SafeStructMap[FileInfo]
	index string
	rule LogRule
	tags []structs.Tag
}

pub struct FileWatcher {
	dir_watch_interval i64 = 5 * time.second
mut:
	log log.Log
	threads []thread
pub mut:
	dirs concurrent.SafeStructMap[DirInfo]
	files concurrent.SafeStructMap[FileInfo]
	service &core.Service
}

pub fn (mut w FileWatcher) watch_dir(dir string, index string, tags []structs.Tag, rule LogRule) {
	real_dir := os.real_path(dir)
	mut info := w.dirs.get_or_create(real_dir, fn () DirInfo {return DirInfo{}})
	if info.t == none {
		info.dir = real_dir
		info.index = index
		info.tags = tags
		info.rule = rule
		info.t = spawn watch_dir_inner(info, w.dir_watch_interval)
	} else {
		info.index = index
		info.tags = tags
		info.rule = rule
	}
}

pub fn (mut w FileWatcher) watch_file(file string, index string, tags []structs.Tag, rule LogRule) {
	path := os.real_path(file)
	mut info := w.files.get_or_create(path, fn () FileInfo {return FileInfo{}})
	if info.watcher == none {
		info.path = path
		info.index = index
		info.tags = tags
		info.rule = rule
		init_file_watcher(mut w, info)
	} else {
		info.index = index
		info.tags = tags
		info.rule = rule
	}
}

fn (mut w FileWatcher) watch_dir_inner(info &DirInfo, interval i64) {
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
			if f in info.files {continue}

			path := os.join_path(info.dir, f)
			file_info := FileInfo {
				index: info.index
				path: path
				tags: info.tags
				rule: info.rule
			}
			init_file_watcher(mut w, file_info)
			info.files.set(f, file_info)
		}
	}
}

fn check_condition(q query.Query, m &map[string]string) !bool {
	match (q) {
		query.NoneQuery {return false}
		query.EmptyQuery {return true}
		query.BaseQuery {
			mut type := ""
			mut value := ""
			for k in m.keys() {
				if !key.starts_with(q.key) {
					continue
				}

				value = m[k]
				strs := k.split(":")
				if strs.len > 1 {
					type = strs[1]
				} else {
					type = "string"
				}
				break
			}
			if type.len == 0 {
				return false
			}

			val1 := meta.DynamicValue.new(type, value, false)!
			mut val2 := meta.DynamicValue{}
			if q.ope == .in {
				val2 = meta.DynamicValue.new(type, q.value, true)!
			} else {
				val2 = meta.DynamicValue.new(type, q.value, false)!
			}
			if q.ope == .gt {
				return val1.compare_to(val2)! > 0
			} else if q.ope == .gte {
				return val1.compare_to(val2)! >= 0
			} else if q.ope == .lt {
				return val1.compare_to(val2)! < 0
			} else if q.ope == .lte {
				return val1.compare_to(val2)! <= 0
			} else if q.ope == .like {
				return val1.like(val2)!
			} else if q.ope == .in {
				return val1.in(val2)!
			} else {
				return error("unsupported symbol: $q.ope")
			}
		}
		query.CompoundQuery {
			left_result := check_condition(q.left, m)!
			if left_result {
				if q.ope == .and {
					return check_condition(q.right, m)!
				} else {
					return true
				}
			} else {
				if q.ope == .and {
					return false
				} else {
					return check_condition(q.right, m)!
				}
			}
		}
	}
}

fn init_file_watcher(mut w FileWatcher, info FileInfo) {
	info.watcher = file.Watcher {
		path: info.path
		on_data: fn [info, mut w] (bytes []u8) bool {
			lines := bytes.bytestr().replace("\r\n", "\n").split("\n")
			if info.rule.log_type == .json {
				for line in lines {
					w.service.index_log(.json, info.index, info.tags, line) or {
						w.log.warn("$line\nfailed to index log: $err")
					}
				}
			} else {
				regex := info.rule.header_regex
				if regex.len == 0 { // single-line log
					for line in lines {
						w.service.index_log(.raw, info.index, info.tags, line) or {
							w.log.warn("$line\nfailed to index log: $err")
						}
					}
				} else { // multi-lines log
					mut log := ""
					for line in lines {
						m := core.parse_log_with_regex(line, regex) or {
							// not matched, this line is not a new log
							log += "\n$line"
							continue
						}
						condition := info.rule.header_condition
						if condition.len != 0 { // need check condition
							q := query.Query.parse(condition) or {
								w.log.warn("exception raised when parse log header condition, condition: $condition error: $err")
								log += "\n$line"
								continue
							}
							if check_condition(q, &m) or {
								w.log.warn("exception raised when check log header condition, line: $line condition: $condition error: $err")
								log += "\n$line"
								continue
							} { // new log
								log = log.trim_space()
								if log.len > 0 {
									w.service.index_log(.raw, info.index, info.tags, log) or {
										w.log.warn("$log\nfailed to index log: $err")
									}
								}
								log = line
							}
						}
						log += "\n$line"
					}
				}
			}
		}
	}
}