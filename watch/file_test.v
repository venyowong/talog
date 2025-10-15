module watch

import core
import core.meta
import core.structs
import extension
import os
import time

fn test_watch_file () {
	mut service := core.Service {
		data_path: "./data/"
	}
	service.setup() or {
		panic("faile to setup service")
	}
	defer {service.close() or {
		panic("faile to close service")
	}}

	mut m := meta.IndexMapping {
		name: "test"
		log_type: .raw
		mapping_time: time.now()
	}
	extension.mapping(mut service, mut m)

	watch_by_config([WatchConfig {
		files: ["/home/venyowong/repos/talog/watch/file_test.v"]
		index: "test"
		rule: LogRule {
			log_type: .raw
		}
		tags: [
			structs.Tag {
				label: "env"
				value: "ubuntu"
			}
		]
	}], mut service)
}

// fn watch_dir() {
// 	mut service := core.Service {
// 		data_path: "./data/"
// 	}
// 	service.setup() or {
// 		panic("faile to setup service")
// 	}
// 	defer {service.close() or {
// 		panic("faile to close service")
// 	}}

// 	mut m := meta.IndexMapping {
// 		name: "equipment_simulator"
// 		log_type: .raw
// 		log_header: "eqp_simulator"
// 		log_regex: "\\[(?P<time>[^\\]]*)\\] \\[(?P<level>[^\\]]*)\\] \\[(?P<name>[^\\]]*)\\] (?P<msg>.*)$"
// 		fields: [
// 			meta.FieldMapping {
// 				name: "time",
// 				type: "string"
// 			},
// 			meta.FieldMapping {
// 				name: "level",
// 				tag_name: "level"
// 				type: "string"
// 			},
// 			meta.FieldMapping {
// 				name: "name",
// 				tag_name: "name"
// 				type: "string"
// 			},
// 			meta.FieldMapping {
// 				name: "msg",
// 				type: "string"
// 			}
// 		]
// 		mapping_time: time.now()
// 	}
// 	extension.mapping(mut service, mut m)

// 	mut watcher := FileWatcher.new(&service) or {
// 		panic("failed to create FileWatcher")
// 	}
// 	defer {watcher.close() or {
// 		panic(err)
// 	}}

// 	mut r := &watcher
// 	spawn r.watch_dir("D:\\Qle.Info.Equipment.Simulator\\logs\\均华", "equipment_simulator", [
// 		structs.Tag {
// 			label: "name",
// 			value: "均华"
// 		}
// 	], LogRule {
// 		log_type: .raw
// 		header_regex: "^\\[(?P<time>[^\\]]+)\\]"
// 	})
// 	os.get_line()
// }
