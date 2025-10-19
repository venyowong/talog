module core

import arrays
import json
import log
import meta
import structs
import os
import regex
import time
import venyowong.concurrent
import venyowong.linq
import venyowong.query
import x.json2

@[heap]
pub struct Service {
mut:
	log log.Log
pub mut:
	indices concurrent.SafeStructMap[Index]
	data_path string
}

pub fn (mut service Service) setup() ! {
	entries := os.ls(service.data_path) or {
		os.mkdir_all(service.data_path)!
        []string{}
    }

	service.log.set_level(.info)
	service.log.set_full_logpath("./log.txt")
	service.log.log_to_console_too()
	defer {service.log.flush()}
	service.log.info("Talog service setup...")
	for entry in entries {
        mut index := Index {
			name: entry
		}
		index.setup(service.data_path) or {
			service.log.error("error occured when $entry index setup")
			continue
		}
		service.indices.set(entry, &index)
    }

	service.mapping[meta.IndexMapping]()!
}

pub fn (mut service Service) check_mapping(mapping meta.IndexMapping) !bool {
	// get last mapping
	mappings := service.get_mappings_by_type(mapping.log_type)!
	last_mapping := arrays.find_first(mappings, fn [mapping] (m meta.IndexMapping) bool {
		return m.name == mapping.name
	})

	if last_mapping != none {
		// check mapping confit
		if mapping.log_type != last_mapping.log_type {
			return error("log type of $mapping.name has changed: $last_mapping.log_type -> $mapping.log_type")
		}
		if mapping.log_header != last_mapping.log_header {
			return error("log header of $mapping.name has changed: $last_mapping.log_header -> $mapping.log_header")
		}
		if mapping.log_regex == last_mapping.log_regex && linq.except(mapping.fields, last_mapping.fields).len == 0 {
			return false
		}
	} else {
		if mapping.log_type == .json && mapping.log_header.len > 0 {
			return error("json log can't have a log header")
		}
		field := arrays.find_first(mapping.fields, fn (f meta.FieldMapping) bool {
			if f.type != "string" && f.type != "time" && f.type != "number" {
				return true
			}
			return false
		})
		if field != none {
			return error("unsupported field type: $field.type")
		}
	}

	return true
}

pub fn (mut service Service) close() ! {
	service.log.info("Talog service closing...")
	defer {service.log.flush()}
	for mut index in service.indices.values() {
		index.save()!
	}
}

pub fn (mut service Service) get_mapping(log_type meta.LogType, name string) !meta.IndexMapping {
	mappings := service.get_mappings_by_type(log_type)!
	return arrays.find_first(mappings, fn [name] (m meta.IndexMapping) bool {
		return m.name == name
	}) or {
		return error("$name has no mapping")
	}
}

pub fn (mut service Service) get_mappings_by_type(log_type meta.LogType) ![]meta.IndexMapping {
	mut idx := service.get_or_create_index("meta.IndexMapping")
	mut mappings := idx.search_logs(query.Query.parse("log_type == $log_type")!, fn (line string, _ []structs.Tag) meta.IndexMapping {
		return json.decode(meta.IndexMapping, line) or {
			panic("the type of log is not json: $line")
		}
	})!
	return group_mappings(mut mappings)
}

pub fn (mut service Service) get_mappings() ![]meta.IndexMapping {
	mut idx := service.get_or_create_index("meta.IndexMapping")
	mut mappings := idx.get_all_logs(fn (line string, _ []structs.Tag) meta.IndexMapping {
		return json.decode(meta.IndexMapping, line) or {
			panic("the type of log is not json: $line")
		}
	})!
	return group_mappings(mut mappings)
}

pub fn (mut service Service) get_or_create_index(name string) &Index {
	return service.indices.get_or_create(name, fn [name, service] () Index { 
		mut index := Index {name: name}
		index.setup(service.data_path)
		return index
	})
}

pub fn (mut service Service) index_log(log_type meta.LogType, name string, 
	tags []structs.Tag, parse_log bool, l string) !bool {
	mapping := service.get_mapping(log_type, name) or {return error("$name has no index mapping")}
	if parse_log {
		if mapping.log_type == .json {
			return service.index_json_log(mapping, tags, l)!
		}

		if mapping.log_regex.len > 0 {
			return service.index_log_with_regex(mapping, tags, l)!
		}
	}

	return service.index_raw_log(mapping, tags, l)!
}

pub fn (mut service Service) index_logs(log_type meta.LogType, name string, 
	tags []structs.Tag, parse_log bool, logs ...string) ! {
	if parse_log {
		for l in logs {
			service.index_log(log_type, name, tags, true, l)!
		}
	} else {
		mapping := service.get_mapping(log_type, name) or {return error("$name has no index mapping")}
		service.index_raw_log(mapping, tags, ...logs)!
	}
}

pub fn (mut service Service) mapping[T]() ! {
	// analyse current mapping
	mut mapping := meta.IndexMapping {
		name: T.name
		log_type: .json
		mapping_time: time.now()
	}
	$for field in T.fields {
		mut field_mapping := meta.FieldMapping {
			name: field.name
			type: get_field_type(field)
		}
		tag := get_attribute(field, "tag", field.name)
		if tag != none {
			field_mapping.tag_name = tag
		}
		index_format := get_attribute(field, "index_format", "") or {""}
		if index_format.len > 0 {
			field_mapping.index_format = index_format
		}
		parse_format := get_attribute(field, "parse_format", "") or {""}
		if parse_format.len > 0 {
			field_mapping.parse_format = parse_format
		}
		mapping.fields << field_mapping
	}

	if service.check_mapping(mapping)! {
		service.save_log(mapping)!
	}
}

pub fn parse_log_with_regex(l string, reg string) !map[string]string {
	mut re := regex.regex_opt(reg)!
	s, _ := re.match_string(l)
	if s < 0 {
		return error("$reg can't match $l")
	}

	mut m := map[string]string{}
	for name in re.group_map.keys() {
		m[name] = re.get_group_by_name(l, name)
	}
	return m
}

pub fn (mut service Service) save_log[T](value T) ! {
	mut tags := []structs.Tag{}
	$for field in T.fields {
		tag := get_attribute(field, "tag", field.name)
		if tag != none {
			mut label := tag
			mut value_str := ""
			$if field.typ is time.Time {
				format := get_attribute(field, "format", "") or {""}
				if format != "" {
					value_str = value.$(field.name).custom_format(format)
				} else {
					value_str = value.$(field.name).custom_format("YYYY-MM-DD HH:mm:ss")
				}
			} $else {
				value_str = value.$(field.name).str()
			}
			tags << structs.Tag {
				label: label
				value: value_str
			}
		}
	}
	mut index := service.get_or_create_index(T.name)
	index.push(tags, json.encode(value))!
}

pub fn (mut service Service) search_logs(log_type meta.LogType, name string, q string) ![]structs.LogModel {
	m := service.get_mapping(log_type, name) or {return []structs.LogModel{}}
	if m.log_type == .json {
		return service.search_json_log(m, q)!
	}

	if m.log_header.len > 0 {
		return service.search_raw_log_with_header(m, q)!
	}

	return service.search_raw_log(m, q)!
}

fn generate_query_for_index(mut q query.Query, mut index Index, m meta.IndexMapping) !query.Query {
	match mut q {
		query.NoneQuery {return q}
		query.EmptyQuery {return q}
		query.BaseQuery {
			if q.ope == query.Symbol.eq || q.ope == query.Symbol.neq {
				return q
			}
			r := unsafe{&q}
			field := arrays.find_first[meta.FieldMapping](m.fields, fn [r] (f meta.FieldMapping) bool {
				return f.tag_name == r.key
			}) or {
				return error("$q.key is not a tag")
			}

			mut values := []string{}
			mut val2 := meta.DynamicValue{}
			if q.ope == .in {
				val2 = meta.DynamicValue.new(field.type, q.value, field.parse_format, true)!
			} else {
				val2 = meta.DynamicValue.new(field.type, q.value, field.parse_format, false)!
			}
			for value in index.get_tag_values(q.key) {
				val1 := meta.DynamicValue.new(field.type, value, field.parse_format, false)!				
				if q.ope == .gt {
					if val1.compare_to(val2)! > 0 {values << value}
				} else if q.ope == .gte {
					if val1.compare_to(val2)! >= 0 {values << value}
				} else if q.ope == .lt {
					if val1.compare_to(val2)! < 0 {values << value}
				} else if q.ope == .lte {
					if val1.compare_to(val2)! <= 0 {values << value}
				} else if q.ope == .like {
					if val1.like(val2)! {values << value}
				} else if q.ope == .in {
					if val1.in(val2)! {values << value}
				}
			}

			if values.len == 0 {
				return query.NoneQuery{}
			}

			mut result := query.Query.new(q.key, .eq, values[0])
			for i := 1; i < values.len; i++ {
				result = result.or(query.BaseQuery {
					key: q.key
					ope: .eq
					value: values[i]
				})
			}
			return result
		}
		query.CompoundQuery {
			q.left = generate_query_for_index(mut q.left, mut index, m)!
			q.right = generate_query_for_index(mut q.right, mut index, m)!
			return q
		}
	}
}

fn get_attribute(field FieldData, key string, default_value string) ?string {
	attribute := arrays.find_first(field.attrs, fn [key] (a string) bool {
		return a.starts_with(key)
	}) or {
		return none
	}

	strs := attribute.split(":")
	if strs.len > 1 {
		return strs[1].trim_space()
	} else {
		return default_value
	}
}

fn get_field_type(field FieldData) string {
	$if field.typ is time.Time {
		return "time"
	} $else $if field.typ is u8 {
		return "number"
	} $else $if field.typ is u16 {
		return "number"
	} $else $if field.typ is u32 {
		return "number"
	} $else $if field.typ is u64 {
		return "number"
	} $else $if field.typ is i8 {
		return "number"
	} $else $if field.typ is i16 {
		return "number"
	} $else $if field.typ is i32 {
		return "number"
	} $else $if field.typ is int {
		return "number"
	} $else $if field.typ is i64 {
		return "number"
	} $else $if field.typ is f32 {
		return "number"
	} $else $if field.typ is f64 {
		return "number"
	} $else {
		return "string"
	}
}

fn group_mappings(mut mappings []meta.IndexMapping) []meta.IndexMapping {
	list := arrays.group_by(mappings, fn (m meta.IndexMapping) string{return m.name}).values()
	return linq.map(list, fn (l []meta.IndexMapping) meta.IndexMapping {
		mut l2 := l.clone()
		return linq.order(mut l2, fn (m1 meta.IndexMapping, m2 meta.IndexMapping) bool {
			return m2.mapping_time > m1.mapping_time
		})[0]
	})
}

fn (mut service Service) index_json_log(m meta.IndexMapping, tags []structs.Tag, l string) !bool {
	obj := json2.decode[json2.Any](l) or {
		return service.index_raw_log(m, tags, l)! // if log is not json format, index it as raw log
	}
	obj_map := obj.as_map()
	field_map := linq.to_map[meta.FieldMapping, string, meta.FieldMapping](m.fields, 
		fn (f meta.FieldMapping) string {return f.name}, fn (f meta.FieldMapping) meta.FieldMapping {return f})
	mut tag_map := linq.to_map[structs.Tag, string, string](tags, 
		fn (t structs.Tag) string {return t.label}, fn (t structs.Tag) string {return t.value})
	for key in obj_map.keys() {
		mut label := key
		mut value := obj_map[key] or {json2.Any{}}.str()
		if key !in field_map {
			continue
		}
		field := field_map[key]
		if field.tag_name.len <= 0 {
			continue
		}
		if field.tag_name.len > 0 {
			label = field.tag_name
		}
		if label in tag_map {continue}

		if field.type == "time" {
			mut t := time.Time{}
			if field.parse_format.len > 0 {
				t = time.parse_format(value, field.parse_format)!
			} else {
				t = time.parse(value)!
			}
			if field.index_format.len > 0 {
				value = t.custom_format(field.index_format)
			} else {
				value = t.custom_format("YYYY-MM-DD HH:mm:ss")
			}
		}
		tag_map[label] = value
	}
	ts := linq.map_to_array[string, string, structs.Tag](tag_map, 
		fn (k string, v string) structs.Tag {return structs.Tag{
			label: k
			value: v
		}})
	mut index := service.get_or_create_index(m.name)
	index.push(ts, l)!
	return true
}

fn (mut service Service) index_log_with_regex(m meta.IndexMapping, tags []structs.Tag, l string) !bool {
	group_map := parse_log_with_regex(l, m.log_regex) or { // if log not match regex, index it as raw log
		return service.index_raw_log(m, tags, l)!
	}

	field_map := linq.to_map[meta.FieldMapping, string, meta.FieldMapping](m.fields, 
		fn (f meta.FieldMapping) string {return f.name}, fn (f meta.FieldMapping) meta.FieldMapping {return f})
	mut tag_map := linq.to_map[structs.Tag, string, string](tags, 
		fn (t structs.Tag) string {return t.label}, fn (t structs.Tag) string {return t.value})
	for name in group_map.keys() {
		mut label := name
		mut value := group_map[name]
		if name !in field_map {
			continue
		}
		field := field_map[name]
		if field.tag_name.len <= 0 {
			continue
		}
		if field.tag_name.len > 0 {
			label = field.tag_name
		}
		if label in tag_map {continue}

		if field.type == "time" {
			mut t := time.Time{}
			if field.parse_format.len > 0 {
				t = time.parse_format(value, field.parse_format)!
			} else {
				t = time.parse(value)!
			}
			if field.index_format.len > 0 {
				value = t.custom_format(field.index_format)
			} else {
				value = t.custom_format("YYYY-MM-DD HH:mm:ss")
			}
		}
		
		tag_map[label] = value
	}
	ts := linq.map_to_array[string, string, structs.Tag](tag_map, 
		fn (k string, v string) structs.Tag {return structs.Tag{
			label: k
			value: v
		}})
	return service.index_raw_log(m, ts, l)!
}

fn (mut service Service) index_raw_log(m meta.IndexMapping, tags []structs.Tag, logs ...string) !bool {
	mut index := service.get_or_create_index(m.name)
	if m.log_header.len > 0 {
		index.push(tags, ...linq.map(logs, fn [m] (l string) string {
			return "$m.log_header $l"
		}))!
	} else {
		index.push(tags, ...logs)!
	}
	return true
}

fn (mut service Service) search_json_log(m meta.IndexMapping, query_str string) ![]structs.LogModel {
	mut index := service.get_or_create_index(m.name)
	mut q := query.Query.parse(query_str)!
	q = generate_query_for_index(mut q, mut index, m)!
	return index.search_logs[structs.LogModel](q, 
		fn [m] (line string, tags []structs.Tag) structs.LogModel {
			return structs.LogModel {
				log: line
				tags: tags
				data: json2.decode[json2.Any](line) or {json2.Any{}}
			}
		})!
}

fn (mut service Service) search_raw_log(m meta.IndexMapping, query_str string) ![]structs.LogModel {
	mut index := service.get_or_create_index(m.name)
	mut q := query.Query.parse(query_str)!
	q = generate_query_for_index(mut q, mut index, m)!
	return index.search_logs[structs.LogModel](q, 
		fn [m] (line string, tags []structs.Tag) structs.LogModel {
			d := parse_log_with_regex(line, m.log_regex) or {map[string]string{}}
			return structs.LogModel {
				log: line
				tags: tags
				data: json2.decode[json2.Any](json2.encode(d)) or {json2.Any{}}
			}
		})!
}

fn (mut service Service) search_raw_log_with_header(m meta.IndexMapping, query_str string) ![]structs.LogModel {
	mut index := service.get_or_create_index(m.name)
	mut q := query.Query.parse(query_str)!
	q = generate_query_for_index(mut q, mut index, m)!
	buckets := index.search(q)!
	mut result := []structs.LogModel{}
	for bucket in buckets {
		logs := index.safe_file.read_by_line[string](bucket.file, fn (line string) ?string {
			return line
		})!
		
		mut temp := ""
		for log in logs {
			if !log.starts_with(m.log_header) {
				temp = "$temp$log\n"
				continue
			}

			if temp.len > 0 { // process last log
				temp = temp.trim_right("\n")
				temp = temp[m.log_header.len+1..]
				d := parse_log_with_regex(temp, m.log_regex)!
				result << structs.LogModel {
					log: temp
					tags: bucket.tags
					data: json2.decode[json2.Any](json2.encode(d))!
				}
			}

			temp = log
		}

		if temp.len > 0 { // process last log
			temp = temp.trim_right("\n")
			temp = temp[m.log_header.len+1..]
			d := parse_log_with_regex(temp, m.log_regex)!
			result << structs.LogModel {
				log: temp
				tags: bucket.tags
				data: json2.decode[json2.Any](json2.encode(d))!
			}
		}
	}
	return result
}