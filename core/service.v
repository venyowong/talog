module core

import concurrent
import os

pub struct Service {
mut:
	indices concurrent.SafeMap[Index]
pub mut:
	data_path string
}

pub fn (mut service Service) setup() {
	entries := os.ls(service.data_path) or {
        eprintln("Cannot find sub directories in $service.data_path: $err")
        return
    }

	for entry in entries {
        mut index := Index {
			name: entry
		}
		index.setup(service.data_path) or {
			println("error occured when $entry index setup")
			continue
		}
		service.indices.set(entry, index)
    }
}

pub fn (mut service Service) close() ! {
	for mut index in service.indices.values() {
		index.save()!
	}
}

pub fn (mut service Service) get_or_create_index(name string) Index {
	return service.indices.get_or_create(name, fn [name] () Index {return Index {name: name}})
}