module meta

import time

@[index: "index_mapping"]
pub struct IndexMapping {
pub mut:
	name string
	log_type LogType @[tag: "log_type"]
	log_header string // header for log
	log_regex string // regex expression for parsing log
	fields []FieldMapping
	mapping_time time.Time @[tag; index_format: "YYYYMM"]
}

pub struct FieldMapping {
pub mut:
	name string
	tag_name string // if tag_name is empty, talog will not index this field
	index_format string // if index_format is not empty, talog will use it to format field and generate index value
	parse_format string // if parse_format is not empty, talog will use it to parse field
	type string // string/time/number
}