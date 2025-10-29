module watch

import core
import core.meta
import core.structs
import json
import models
import net.http

pub struct Indexer {
pub mut:
	host string
	service ?core.Service
}

pub fn (mut indexer Indexer) index_log(log_type meta.LogType, name string, tags []structs.Tag, l string) !bool {
	if indexer.service != none {
		return indexer.service.index_log(log_type, name, tags, true, l)!
	} else {
		res := http.post("${indexer.host}/index", json.encode(models.IndexLogReq {
			name: name
			log_type: log_type
			log: l
			tags: tags
		}))!
		if res.status() != .ok {
			return error("failed to post ${indexer.host}/index, status: ${res.status()}")
		}
		result := json.decode(models.Result, res.body)!
		if result.code != 0 {
			return error(result.msg)
		}

		return true
	}
}
