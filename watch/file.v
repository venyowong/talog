module watch

import core
import core.meta
import core.structs
import log
import json
import os
import time
import venyowong.concurrent
import venyowong.file
import venyowong.query
import v.util

pub struct FileInfo {
pub mut:
	index string
	last_mtime i64
	next_pos u64
	path string
	rule LogRule
	tags []structs.Tag
}

pub fn watch_by_config(configs []WatchConfig, mut service core.Service) {
	mut l := log.Log{}
	l.set_level(.debug)
	l.set_full_logpath("./log.txt")
	l.log_to_console_too()
	l.info("file watcher setup...")
	mut r_l := &l
	watching := []string{}
	for {
		for c in configs {
			for f in c.files {
				path := os.real_path(f)
				if path in watching {continue}

				mut info := FileInfo {
					path: path
					index: c.index
					tags: c.tags
					rule: c.rule
				}
				mut r_info := &info
				spawn r_info.watching(mut service, mut r_l)
			}
			for dir in c.dirs {
				real_dir := os.real_path(dir)
				files := os.ls(real_dir) or {[]string{}}
				for f in files {
					path := os.real_path(f)
					if path in watching {continue}

					mut info := FileInfo {
						path: path
						index: c.index
						tags: c.tags
						rule: c.rule
					}
					mut r_info := &info
					spawn r_info.watching(mut service, mut r_l)
				}
			}
		}
		time.sleep(5 * time.second)
	}
}

pub fn (mut info FileInfo) watching(mut service core.Service, mut l log.Log) {
	meta_path := "${info.path}.wch"
	info2 := json.decode(FileInfo, os.read_file(meta_path) or {""}) or {FileInfo{}}
	info.last_mtime = info2.last_mtime
	info.next_pos = info2.next_pos

	shared w := file.Watcher {
		path: info.path
		last_mtime: info.last_mtime
		next_pos: info.next_pos
	}
	spawn w.start()

	for {
		concurrent.spin_wait(10 * time.millisecond, 5 * time.second, 20, 0, fn [shared w]() bool {
			rlock w {
				return w.increments.len > 0
			}
		}) or {
			return
		}

		lock w {
			increment := w.increments.pop_left()
			if increment.data.len <= 0 {continue}

			lines := increment.data.bytestr().replace("\r\n", "\n").split("\n")
			l.debug("$info.path has $lines.len lines")
			if info.rule.log_type == .json {
				for line in lines {
					service.index_log(.json, info.index, info.tags, line) or {
						l.warn("$line\nfailed to index log: $err")
						continue
					}
				}
			} else {
				regex := info.rule.header_regex
				if regex.len == 0 { // single-line log
					for line in lines {
						service.index_log(.raw, info.index, info.tags, line) or {
							l.warn("$line\nfailed to index log: $err")
							continue
						}
					}
				} else { // multi-lines log
					mut single_log := ""
					for lin in lines {
						line := util.skip_bom(lin)
						m := core.parse_log_with_regex(line, regex) or {
							// not matched, this line is not a new log
							single_log += "\n$line"
							continue
						}
						condition := info.rule.header_condition
						if condition.len != 0 { // need check condition
							q := query.Query.parse(condition) or {
								l.warn("exception raised when parse log header condition, condition: $condition error: $err")
								single_log += "\n$line"
								continue
							}
							if check_condition(q, m, info.rule.headers) or {
								l.warn("exception raised when check log header condition, line: $line condition: $condition error: $err")
								single_log += "\n$line"
								continue
							} { // new log
								single_log = single_log.trim_space()
								if single_log.len > 0 {
									service.index_log(.raw, info.index, info.tags, single_log) or {
										l.warn("$single_log\nfailed to index log: $err")
									}
								}
								single_log = line
							}
						} else { // new log
							single_log = single_log.trim_space()
							if single_log.len > 0 {
								service.index_log(.raw, info.index, info.tags, single_log) or {
									l.warn("$single_log\nfailed to index log: $err")
								}
							}
							single_log = line
						}
					}
					single_log = single_log.trim_space()
					if single_log.len > 0 {
						service.index_log(.raw, info.index, info.tags, single_log) or {
							l.warn("$single_log\nfailed to index log: $err")
						}
					}
				}
			}
			info.last_mtime = increment.last_mtime
			info.next_pos = increment.next_pos
			os.write_file(meta_path, json.encode(info)) or {
				l.warn("failed to write file $meta_path: $err")
			}
		}
	}
}

fn check_condition(q query.Query, m map[string]string, headers map[string]LogHeader) !bool {
	match q {
		query.NoneQuery {return false}
		query.EmptyQuery {return true}
		query.BaseQuery {
			value := m[q.key]
			if value.len == 0 {
				return false
			}
			mut h := headers[q.key]
			if h.type.len == 0 {
				h.type = "string"
			}

			val1 := meta.DynamicValue.new(h.type, value, h.format, false)!
			mut val2 := meta.DynamicValue{}
			if q.ope == .in {
				val2 = meta.DynamicValue.new(h.type, q.value, h.format, true)!
			} else {
				val2 = meta.DynamicValue.new(h.type, q.value, h.format, false)!
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
			left_result := check_condition(q.left, m, headers)!
			if left_result {
				if q.ope == .and {
					return check_condition(q.right, m, headers)!
				} else {
					return true
				}
			} else {
				if q.ope == .and {
					return false
				} else {
					return check_condition(q.right, m, headers)!
				}
			}
		}
	}
}