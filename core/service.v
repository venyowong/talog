module core

import arrays
import json
import log
import meta
import models
import os
import time
import venyowong.concurrent

pub struct Service {
mut:
	log log.Log
pub mut:
	indices concurrent.SafeStructMap[Index]
	data_path string
}

pub fn (mut service Service) setup() ! {
	service.log.info("Talog service setup...")
	entries := os.ls(service.data_path) or {
		os.mkdir_all(service.data_path)!
        []string{}
    }

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

pub fn (mut service Service) close() ! {
	service.log.info("Talog service closing...")
	for mut index in service.indices.values() {
		index.save()!
	}
}

pub fn (mut service Service) get_or_create_index(name string) &Index {
	return service.indices.get_or_create(name, fn [name, service] () Index { 
		mut index := Index {name: name}
		index.setup(service.data_path)
		return index
	})
}

pub fn (mut service Service) mapping[T]() ! {
	// analyse current mapping
	mut mapping := meta.IndexMapping {
		name: T.name
		log_type: 1
		mapping_time: time.now()
	}
	$for field in T.fields {
		mut field_mapping := meta.FieldMapping {
			name: field.name
		}
		tag := get_attribute(field, "tag", field.name)
		if tag != none {
			field_mapping.tag_name = tag
		}
		format := get_attribute(field, "format", "") or {""}
		if format != "" {
			field_mapping.format = format
		}
		mapping.fields << field_mapping
	}

	// get last mapping
	mut index := service.get_or_create_index(T.name)
	mappings := index.search_logs_by_exp("log_type == 1", fn (line string, _ []models.Tag) meta.IndexMapping {
		return json.decode(meta.IndexMapping, line) or {
			panic("the type of log is not json: $line")
		}
	})!
	last_mapping := arrays.find_first(mappings, fn [mapping] (m meta.IndexMapping) bool {
		return m.name == mapping.name
	})

	if last_mapping != none {
		// check mapping confit
		if mapping.log_type != last_mapping.log_type {
			panic("log type of $mapping.name has changed: $last_mapping.log_type -> $mapping.log_type")
		}
		if mapping.log_header != last_mapping.log_header {
			panic("log header of $mapping.name has changed: $last_mapping.log_header -> $mapping.log_header")
		}
	}

	// save mapping
	service.save_log(mapping)!
}

pub fn (mut service Service) save_log[T](value T) ! {
	mut tags := []models.Tag{}
	$for field in T.fields {
		tag := get_attribute(field, "tag", field.name)
		if tag != none {
			mut label := tag
			mut value_str := ""
			$if field.typ is time.Time {
				format := get_attribute(field, "format", "") or {""}
				if format != "" {
					value_str = value.$(field.name).custom_format("YYYY-MM-DD HH:mm:ss")
				} else {
					value_str = value.$(field.name).custom_format(format)
				}
			} $else {
				value_str = value.$(field.name).str()
			}
			tags << models.Tag {
				label: label
				value: value_str
			}
		}
	}
	mut index := service.get_or_create_index(T.name)
	index.push(tags, json.encode(value))!
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