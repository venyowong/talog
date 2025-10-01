module meta

import time

@[index: "index_mapping"]
pub struct IndexMapping {
pub mut:
	name string
	log_type int @[tag: "log_type"] // 0 log 1 json
	log_header string // header for log
	log_regex string // regex expression for parsing log
	fields []FieldMapping
	mapping_time time.Time @[tag; format: "YYYYMM"]
}

pub struct FieldMapping {
pub mut:
	name string
	tag_name string // if tag_name is empty, talog will not index this field
	format string // if format is not empty, talog will use it to format field and generate index value
	type string // string/time/number
}